#include <QApplication>
#include <QCommandLineParser>
#include <QCommandLineOption>
#include <QLocalServer>
#include <QLocalSocket>
#include <QDebug>
#include <QFont>
#include <QPalette>
#include <QColor>
#include "MainWindow.h"
#include "Theme.h"

int main(int argc, char *argv[])
{
    // Enable high DPI scaling
    QApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QApplication app(argc, argv);
    app.setApplicationName("Glass Player");
    app.setOrganizationName("Glass Player");
    app.setWindowIcon(QIcon(":/icons/app.svg"));

    // Set application-wide font matching WinUI Segoe UI Variable Text (or Segoe UI fallback)
    QFont font("Segoe UI Variable Text", 10);
    font.setFamilies(QStringList() << "Segoe UI Variable Text" << "Segoe UI" << "Arial");
    app.setFont(font);

    // Dark Fluent Palette
    QPalette darkPalette;
    darkPalette.setColor(QPalette::Window, QColor(32, 32, 32));
    darkPalette.setColor(QPalette::WindowText, QColor(255, 255, 255, 237));
    darkPalette.setColor(QPalette::Base, QColor(20, 20, 20));
    darkPalette.setColor(QPalette::AlternateBase, QColor(32, 32, 32));
    darkPalette.setColor(QPalette::ToolTipBase, QColor(32, 32, 32));
    darkPalette.setColor(QPalette::ToolTipText, QColor(255, 255, 255, 237));
    darkPalette.setColor(QPalette::Text, QColor(255, 255, 255, 237));
    darkPalette.setColor(QPalette::Button, QColor(45, 45, 45));
    darkPalette.setColor(QPalette::ButtonText, QColor(255, 255, 255, 237));
    darkPalette.setColor(QPalette::BrightText, Qt::white);
    darkPalette.setColor(QPalette::Link, QColor(96, 205, 255));
    darkPalette.setColor(QPalette::Highlight, QColor(96, 205, 255, 51));
    darkPalette.setColor(QPalette::HighlightedText, QColor(96, 205, 255));
    darkPalette.setColor(QPalette::Disabled, QPalette::WindowText, QColor(255, 255, 255, 115));
    darkPalette.setColor(QPalette::Disabled, QPalette::Text, QColor(255, 255, 255, 115));
    darkPalette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(255, 255, 255, 115));
    app.setPalette(darkPalette);

    // Global QToolTip style
    app.setStyleSheet("QToolTip { color: rgba(255, 255, 255, 237); background-color: rgba(32, 32, 32, 240); border: 1px solid rgba(255, 255, 255, 46); border-radius: 4px; padding: 4px 8px; }");

    const QString serverName = "GlassPlayerIPCServer";
    
    // Check if arguments are provided to control the player
    QStringList cmdArgs = app.arguments();
    cmdArgs.removeFirst(); // Remove executable path
    
    if (!cmdArgs.isEmpty()) {
        QLocalSocket socket;
        socket.connectToServer(serverName);
        if (socket.waitForConnected(500)) {
            QString command = cmdArgs.join(" ");
            socket.write(command.toUtf8());
            socket.waitForBytesWritten(1000);
            return 0; // Exit secondary instance immediately after sending command
        }
    }

    // This is the primary instance. Clean up previous socket server leftovers.
    QLocalServer::removeServer(serverName);

    QLocalServer server;
    if (!server.listen(serverName)) {
        qWarning() << "Failed to start local IPC server:" << server.errorString();
    }

    MainWindow w;

    // Connect the local IPC server to execute received CLI commands on the player
    QObject::connect(&server, &QLocalServer::newConnection, &w, [&server, &w]() {
        QLocalSocket *socket = server.nextPendingConnection();
        if (socket) {
            QObject::connect(socket, &QLocalSocket::readyRead, socket, [&w, socket]() {
                QString command = QString::fromUtf8(socket->readAll()).trimmed();
                if (!command.isEmpty()) {
                    w.executeCommand(command);
                }
            });
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QLocalSocket::deleteLater);
        }
    });

    QCommandLineParser parser;
    parser.setApplicationDescription("Glass Player");
    parser.addHelpOption();

    QCommandLineOption anime4kOption(QStringList() << "a" << "anime4k",
        "Enable Anime4K with preset <preset> (e.g. ModeA, ModeB, ModeC, ModeAA, ModeBB, ModeCA).",
        "preset");
    parser.addOption(anime4kOption);

    parser.addPositionalArgument("file", "The file to open.");

    parser.process(app);

    if (parser.isSet(anime4kOption)) {
        w.setAnime4kPreset(parser.value(anime4kOption));
    }

    const QStringList args = parser.positionalArguments();
    if (!args.isEmpty()) {
        w.suppressWelcome();   // Don't show welcome when a file is opened directly
        w.openFile(args.first());
        w.show();
    } else {
        // Show the welcome screen dialog first. Only show the main window if accepted.
        if (w.shouldShowWelcome()) {
            if (w.runWelcomeScreen() == QDialog::Accepted) {
                w.show();
            } else {
                return 0; // Clean exit without showing the black window
            }
        } else {
            w.show();
        }
    }

    return app.exec();
}
