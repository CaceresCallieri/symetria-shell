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
    // Cancel in-flight work without blocking the GUI thread.
    // The thread pool will finish the job on its own; the watcher is parented
    // to this object and will be collected when the parent is destroyed, but we
    // disconnect it first to prevent the finished signal firing after destruction.
    if (m_watcher) {
        m_watcher->disconnect();
        m_watcher->cancel();
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

// Sets m_resolvedUrl and emits resolvedUrlChanged. Also clears m_loading and
// emits loadingChanged if it was set. Used by all synchronous return paths.
void PreviewImageHelper::applyResolvedUrl(const QString& url) {
    if (m_resolvedUrl != url) {
        m_resolvedUrl = url;
        emit resolvedUrlChanged();
    }
    if (m_loading) {
        m_loading = false;
        emit loadingChanged();
    }
}

void PreviewImageHelper::processSource() {
    // Cancel any in-flight async work without blocking the GUI thread.
    // Disconnect signals first so the old watcher's finished signal cannot
    // fire against a stale this-pointer after we null out m_watcher.
    if (m_watcher) {
        m_watcher->disconnect();
        m_watcher->cancel();
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
        applyResolvedUrl(QStringLiteral("file://") + m_source);
        return;
    }

    // PDF — check cache first, then generate asynchronously
    const QFileInfo info(m_source);
    const auto cacheKey = QCryptographicHash::hash(
        (m_source + QStringLiteral(":") + QString::number(info.lastModified().toSecsSinceEpoch())).toUtf8(),
        QCryptographicHash::Sha1
    ).toHex();
    const auto cachePath = cacheDir() + QStringLiteral("/") + cacheKey + QStringLiteral(".png");

    // Cache hit — return immediately without spinning up a thread
    if (QFileInfo::exists(cachePath)) {
        applyResolvedUrl(QStringLiteral("file://") + cachePath);
        return;
    }

    // Cache miss — render asynchronously
    if (!m_loading) {
        m_loading = true;
        emit loadingChanged();
    }

    // Capture both the source string and the watcher pointer so the lambda
    // is self-contained and does not touch m_watcher after it has been nulled
    // or replaced by a subsequent processSource() call.
    const auto capturedSource = m_source;

    m_watcher = new QFutureWatcher<QString>(this);
    connect(m_watcher, &QFutureWatcher<QString>::finished, this,
            [this, capturedSource, watcher = m_watcher]() {
        // Stale result — source changed while we were rendering
        if (m_source != capturedSource) return;

        const auto result = watcher->result();
        watcher->deleteLater();
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
    // Use a fast suffix check to avoid opening the file on the GUI thread.
    // The reader-based format detection would perform synchronous I/O here.
    return path.endsWith(QStringLiteral(".pdf"), Qt::CaseInsensitive);
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

const QString& PreviewImageHelper::cacheDir() {
    // Compute once per process lifetime — QStandardPaths does not change at runtime.
    static const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/preview");
    return dir;
}

} // namespace symmetria::models
