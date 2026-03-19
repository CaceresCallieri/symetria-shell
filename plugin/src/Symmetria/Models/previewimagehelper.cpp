#include "previewimagehelper.hpp"

#include <qcryptographichash.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qimage.h>
#include <qimagereader.h>
#include <qstandardpaths.h>
#include <qtconcurrentrun.h>

namespace symmetria::models {

PreviewImageHelper::PreviewImageHelper(QObject* parent)
    : QObject(parent) {}

PreviewImageHelper::~PreviewImageHelper() {
    if (m_watcher) {
        m_watcher->cancel();
        m_watcher->waitForFinished();
    }
}

QString PreviewImageHelper::source() const { return m_source; }

void PreviewImageHelper::setSource(const QString& path) {
    if (m_source == path) return;
    m_source = path;
    emit sourceChanged();
    processSource();
}

QString PreviewImageHelper::resolvedUrl() const { return m_resolvedUrl; }

bool PreviewImageHelper::loading() const { return m_loading; }

void PreviewImageHelper::processSource() {
    // Cancel any in-flight async work
    if (m_watcher) {
        m_watcher->cancel();
        m_watcher->waitForFinished();
        m_watcher->deleteLater();
        m_watcher = nullptr;
    }

    // Empty source — clear everything
    if (m_source.isEmpty()) {
        if (!m_resolvedUrl.isEmpty()) {
            m_resolvedUrl.clear();
            emit resolvedUrlChanged();
        }
        if (m_loading) {
            m_loading = false;
            emit loadingChanged();
        }
        return;
    }

    // Non-PDF files — passthrough, no compositing needed
    if (!needsBackgroundCompositing(m_source)) {
        const auto url = QStringLiteral("file://") + m_source;
        if (m_resolvedUrl != url) {
            m_resolvedUrl = url;
            emit resolvedUrlChanged();
        }
        if (m_loading) {
            m_loading = false;
            emit loadingChanged();
        }
        return;
    }

    // PDF — check cache first, then generate asynchronously
    const QFileInfo info(m_source);
    const auto cacheKey = QCryptographicHash::hash(
        (m_source + QStringLiteral(":") + QString::number(info.lastModified().toSecsSinceEpoch())).toUtf8(),
        QCryptographicHash::Sha1
    ).toHex();
    const auto cachePath = cacheDir() + QStringLiteral("/") + cacheKey + QStringLiteral(".png");

    // Cache hit — return immediately
    if (QFileInfo::exists(cachePath)) {
        const auto url = QStringLiteral("file://") + cachePath;
        if (m_resolvedUrl != url) {
            m_resolvedUrl = url;
            emit resolvedUrlChanged();
        }
        if (m_loading) {
            m_loading = false;
            emit loadingChanged();
        }
        return;
    }

    // Cache miss — render asynchronously
    if (!m_loading) {
        m_loading = true;
        emit loadingChanged();
    }

    // Capture source for lambda closure (detect stale results)
    const auto capturedSource = m_source;

    m_watcher = new QFutureWatcher<QString>(this);
    connect(m_watcher, &QFutureWatcher<QString>::finished, this, [this, capturedSource]() {
        // Stale result — source changed while we were rendering
        if (m_source != capturedSource) return;

        const auto result = m_watcher->result();
        m_watcher->deleteLater();
        m_watcher = nullptr;

        m_loading = false;
        emit loadingChanged();

        if (!result.isEmpty()) {
            m_resolvedUrl = QStringLiteral("file://") + result;
        } else {
            // Render failed — fall back to raw file URL
            m_resolvedUrl = QStringLiteral("file://") + m_source;
        }
        emit resolvedUrlChanged();
    });

    m_watcher->setFuture(QtConcurrent::run(generateCachedPreview, m_source, cachePath));
}

bool PreviewImageHelper::needsBackgroundCompositing(const QString& path) {
    QImageReader reader(path);
    return reader.canRead() && reader.format() == "pdf";
}

QString PreviewImageHelper::generateCachedPreview(const QString& sourcePath, const QString& cachePath) {
    QImageReader reader(sourcePath);
    reader.setBackgroundColor(Qt::white);

    const QImage image = reader.read();
    if (image.isNull()) return {};

    // Ensure cache directory exists
    QDir().mkpath(QFileInfo(cachePath).absolutePath());

    if (!image.save(cachePath, "PNG")) return {};

    return cachePath;
}

QString PreviewImageHelper::cacheDir() {
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/preview");
}

} // namespace symmetria::models
