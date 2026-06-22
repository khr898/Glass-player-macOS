#include <windows.h>
#undef GetCurrentTime
#include <MddBootstrap.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <fstream>
#include <iomanip>

#include "MainWindow.h"
#include "WelcomeWindow.h"

inline void LogMessage(const std::wstring& msg)
{
    wchar_t tempPath[MAX_PATH];
    if (GetTempPathW(MAX_PATH, tempPath)) {
        std::wstring logPath = std::wstring(tempPath) + L"glass_player_debug.log";
        std::wofstream logFile(logPath, std::ios::app);
        if (logFile.is_open()) {
            logFile << msg << std::endl;
        }
    }
}

// Custom App class inheriting from WinUI 3 Application
struct App : winrt::Microsoft::UI::Xaml::ApplicationT<App>
{
    App(std::wstring const& cmdLine) : m_cmdLine(cmdLine)
    {
        LogMessage(L"App::App - Constructor called");
    }

    void OnLaunched(winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs const&)
    {
        LogMessage(L"App::OnLaunched - Started");
        // Parse arguments for options and file path
        std::wstring fileToOpen;
        std::wstring anime4kPreset;
        
        int argc = 0;
        LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
        if (argv) {
            for (int i = 1; i < argc; ++i) {
                std::wstring arg = argv[i];
                if ((arg == L"-a" || arg == L"--anime4k") && i + 1 < argc) {
                    anime4kPreset = argv[++i];
                } else if (arg[0] != L'-') {
                    fileToOpen = arg;
                }
            }
            LocalFree(argv);
        }

        LogMessage(L"App::OnLaunched - Creating MainWindow");
        // Initialize and display main window
        m_mainWindow = std::make_shared<MainWindow>();
        LogMessage(L"App::OnLaunched - MainWindow created");
        
        if (!anime4kPreset.empty()) {
            m_mainWindow->setAnime4kPreset(anime4kPreset);
        }

        if (!fileToOpen.empty()) {
            LogMessage(L"App::OnLaunched - Opening file: " + fileToOpen);
            m_mainWindow->suppressWelcome();
            m_mainWindow->openFile(fileToOpen);
            m_mainWindow->show();
        } else {
            if (m_mainWindow->shouldShowWelcome()) {
                LogMessage(L"App::OnLaunched - Creating WelcomeWindow");
                m_welcomeWindow = std::make_shared<WelcomeWindow>();
                
                // Set up events on the welcome screen
                m_welcomeWindow->fileOpened([this](std::wstring const& path) {
                    m_welcomeWindow->close();
                    m_mainWindow->openFile(path);
                    m_mainWindow->show();
                });
                
                m_welcomeWindow->openRcloneBrowser([this]() {
                    m_welcomeWindow->close();
                    m_mainWindow->openRcloneBrowserDirectly();
                    m_mainWindow->show();
                });

                LogMessage(L"App::OnLaunched - Showing WelcomeWindow");
                // Show welcome screen. Only show main window if a file is loaded or browser is open.
                m_welcomeWindow->show();
            } else {
                LogMessage(L"App::OnLaunched - Showing MainWindow directly");
                m_mainWindow->show();
            }
        }
        LogMessage(L"App::OnLaunched - Completed");
    }

private:
    std::wstring m_cmdLine;
    std::shared_ptr<MainWindow> m_mainWindow{ nullptr };
    std::shared_ptr<WelcomeWindow> m_welcomeWindow{ nullptr };
};

int APIENTRY wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow)
{
    LogMessage(L"wWinMain - Started");
    // 1. Single-instance check
    HANDLE hMutex = CreateMutexW(nullptr, TRUE, L"Local\\GlassPlayerMutex");
    if (hMutex == nullptr) {
        LogMessage(L"wWinMain - CreateMutex failed");
        return 0;
    }
    
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        LogMessage(L"wWinMain - Instance already exists, forwarding arguments");
        // Locate primary instance window
        HWND hwndPrimary = nullptr;
        for (int i = 0; i < 5; ++i) {
            hwndPrimary = FindWindowW(L"GlassPlayerVideoWindowClass", nullptr);
            if (hwndPrimary) break;
            Sleep(100);
        }
        
        if (hwndPrimary) {
            // Forward CLI arguments to the active instance
            int argc = 0;
            LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
            if (argv && argc > 1) {
                std::wstring command;
                for (int i = 1; i < argc; ++i) {
                    if (i > 1) command += L" ";
                    command += argv[i];
                }
                
                COPYDATASTRUCT cds;
                cds.dwData = 1; // command arguments code
                cds.cbData = (DWORD)((command.length() + 1) * sizeof(wchar_t));
                cds.lpData = (void*)command.c_str();
                
                SendMessageW(hwndPrimary, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
                LocalFree(argv);
                LogMessage(L"wWinMain - Arguments forwarded: " + command);
            } else {
                LogMessage(L"wWinMain - No arguments to forward");
            }
            // Focus primary window
            ShowWindow(hwndPrimary, SW_RESTORE);
            SetForegroundWindow(hwndPrimary);
        } else {
            LogMessage(L"wWinMain - Primary window not found");
        }
        CloseHandle(hMutex);
        LogMessage(L"wWinMain - Exiting second instance");
        return 0;
    }

    LogMessage(L"wWinMain - Primary instance, initializing Windows App SDK bootstrapper");
    // 2. Initialize Windows App SDK bootstrap
    // Major 1, Minor 5 (0x00010005)
    HRESULT hr = MddBootstrapInitialize2(
        0x00010005,
        L"",
        PACKAGE_VERSION{ 0 },
        MddBootstrapInitializeOptions_OnError_DebugBreak
    );
    
    if (FAILED(hr)) {
        LogMessage(L"wWinMain - MddBootstrapInitialize2 failed with hr=" + std::to_wstring(hr));
        MessageBoxW(nullptr, L"Failed to initialize Windows App SDK bootstrap. Please ensure Windows App Runtime is installed.", L"Glass Player - Error", MB_OK | MB_ICONERROR);
        CloseHandle(hMutex);
        return hr;
    }

    LogMessage(L"wWinMain - Bootstrapper initialized successfully. Initializing apartment");
    // 3. Initialize Threading Apartment
    winrt::init_apartment(winrt::apartment_type::single_threaded);

    LogMessage(L"wWinMain - Starting WinUI 3 Application loop");
    // 4. Start WinUI 3 Application Loop
    winrt::Microsoft::UI::Xaml::Application::Start([&](auto&&) {
        try {
            LogMessage(L"wWinMain - Inside Application::Start, creating App");
            winrt::make<App>(lpCmdLine);
            LogMessage(L"wWinMain - App created successfully");
        } catch (winrt::hresult_error const& ex) {
            LogMessage(L"wWinMain - hresult_error: " + std::wstring(ex.message()));
        } catch (std::exception const& ex) {
            LogMessage(L"wWinMain - std::exception: " + std::wstring(winrt::to_hstring(ex.what())));
        } catch (...) {
            LogMessage(L"wWinMain - Unknown exception in Application::Start");
        }
    });

    LogMessage(L"wWinMain - Application loop exited. Shutting down bootstrapper");
    // 5. Clean up
    MddBootstrapShutdown();
    CloseHandle(hMutex);
    
    LogMessage(L"wWinMain - Completed and exiting");
    return 0;
}
