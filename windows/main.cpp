#include <QApplication>
#include "MainWindow.h"

int main(int argc, char *argv[])
{
    // Enable high DPI scaling
    QApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QApplication app(argc, argv);
    app.setApplicationName("Glass Player");
    app.setOrganizationName("Glass Player");

    MainWindow w;

    // Pass command line arguments to open files if provided
    if (argc > 1) {
        w.openFile(QString::fromUtf8(argv[1]));
    }

    w.show();
    return app.exec();
}
