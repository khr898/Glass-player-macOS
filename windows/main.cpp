#include <QApplication>
#include <QCommandLineParser>
#include <QCommandLineOption>
#include "MainWindow.h"

int main(int argc, char *argv[])
{
    // Enable high DPI scaling
    QApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QApplication app(argc, argv);
    app.setApplicationName("Glass Player");
    app.setOrganizationName("Glass Player");

    QCommandLineParser parser;
    parser.setApplicationDescription("Glass Player");
    parser.addHelpOption();

    QCommandLineOption anime4kOption(QStringList() << "a" << "anime4k",
        "Enable Anime4K with preset <preset> (e.g. ModeA, ModeB, ModeC, ModeAA, ModeBB, ModeCA).",
        "preset");
    parser.addOption(anime4kOption);

    parser.addPositionalArgument("file", "The file to open.");

    parser.process(app);

    MainWindow w;

    if (parser.isSet(anime4kOption)) {
        w.setAnime4kPreset(parser.value(anime4kOption));
    }

    const QStringList args = parser.positionalArguments();
    if (!args.isEmpty()) {
        w.suppressWelcome();   // Don't show welcome when a file is opened directly
        w.openFile(args.first());
    }

    w.show();
    return app.exec();
}
