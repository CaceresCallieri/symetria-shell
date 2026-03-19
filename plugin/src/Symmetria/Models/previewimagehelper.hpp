#pragma once

#include <qfuturewatcher.h>
#include <qobject.h>
#include <qqmlintegration.h>

namespace symmetria::models {

class PreviewImageHelper : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QString resolvedUrl READ resolvedUrl NOTIFY resolvedUrlChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    explicit PreviewImageHelper(QObject* parent = nullptr);
    ~PreviewImageHelper() override;

    [[nodiscard]] QString source() const;
    void setSource(const QString& path);

    [[nodiscard]] QString resolvedUrl() const;
    [[nodiscard]] bool loading() const;

signals:
    void sourceChanged();
    void resolvedUrlChanged();
    void loadingChanged();

private:
    void processSource();
    void applyResolvedUrl(const QString& url);
    static bool needsBackgroundCompositing(const QString& path);
    static QString generateCachedPreview(const QString& sourcePath, const QString& cachePath);
    static const QString& cacheDir();

    QString m_source;
    QString m_resolvedUrl;
    bool m_loading = false;
    QFutureWatcher<QString>* m_watcher = nullptr;
};

} // namespace symmetria::models
