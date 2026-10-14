#pragma once

#include <qimage.h>
#include <qmutex.h>
#include <qobject.h>
#include <qset.h>
#include <qsize.h>
#include <qstring.h>

namespace caelestia::images {

class ImageCacher : public QObject {
    Q_OBJECT

public:
    enum class FillMode : quint8 {
        Crop,
        Fit,
        Stretch,
    };

    static ImageCacher* instance();

    static const QString& cacheDir();
    static QString cachePathFor(const QString& sourcePath, const QSize& size, FillMode fillMode);
    static QImage render(const QString& sourcePath, const QSize& size, FillMode fillMode);
    static bool store(const QImage& image, const QString& cachePath);

    void schedule(const QString& sourcePath, const QSize& size, FillMode fillMode);
    void schedule(const QString& sourcePath, const QString& cachePath, const QSize& size, FillMode fillMode);

private:
    explicit ImageCacher(QObject* parent = nullptr);

    static void runJob(const QString& sourcePath, const QString& cachePath, const QSize& size, FillMode fillMode);

    QMutex m_mutex;
    QSet<QString> m_inflight;
};

} // namespace caelestia::images
