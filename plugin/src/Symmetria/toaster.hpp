#pragma once

#include <qfile.h>
#include <qjsvalue.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qset.h>
#include <qtimer.h>

namespace symmetria {

class Toast : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Toast instances can only be retrieved from a Toaster")

    Q_PROPERTY(bool closed READ closed NOTIFY closedChanged)
    Q_PROPERTY(QString key READ key CONSTANT)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(QString icon READ icon NOTIFY iconChanged)
    Q_PROPERTY(QString imagePath READ imagePath CONSTANT)
    Q_PROPERTY(int timeout READ timeout NOTIFY timeoutChanged)
    Q_PROPERTY(Type type READ type NOTIFY typeChanged)
    Q_PROPERTY(bool hasAction READ hasAction CONSTANT)

public:
    enum class Type {
        Info = 0,
        Success,
        Warning,
        Error
    };
    Q_ENUM(Type)

    explicit Toast(const QString& title, const QString& message, const QString& icon, Type type, int timeout,
        const QString& imagePath = QString(), QJSValue action = QJSValue(),
        const QString& key = QString(), QObject* parent = nullptr);

    [[nodiscard]] bool closed() const;
    [[nodiscard]] QString key() const;
    [[nodiscard]] QString title() const;
    [[nodiscard]] QString message() const;
    [[nodiscard]] QString icon() const;
    [[nodiscard]] QString imagePath() const;
    [[nodiscard]] int timeout() const;
    [[nodiscard]] Type type() const;
    [[nodiscard]] bool hasAction() const;

    // Updates the toast content in-place. Also callable directly from QML if a
    // caller holds a toast reference, consistent with close()/lock()/unlock().
    Q_INVOKABLE void update(const QString& title, const QString& message, const QString& icon, Type type, int timeout = 0);
    Q_INVOKABLE void invokeAction();
    Q_INVOKABLE void close();
    Q_INVOKABLE void lock(QObject* sender);
    Q_INVOKABLE void unlock(QObject* sender);

signals:
    void closedChanged();
    void titleChanged();
    void messageChanged();
    void iconChanged();
    void timeoutChanged();
    void typeChanged();
    void finishedClose();

private:
    void applyDefaults();

    QSet<QObject*> m_locks;
    QTimer* m_timer;

    bool m_closed;
    QString m_key;
    QString m_title;
    QString m_message;
    QString m_icon;
    QString m_imagePath;
    QJSValue m_action;
    Type m_type;
    int m_timeout;
    bool m_hasAction;
};

class Toaster : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QQmlListProperty<symmetria::Toast> toasts READ toasts NOTIFY toastsChanged)

public:
    explicit Toaster(QObject* parent = nullptr);

    [[nodiscard]] QQmlListProperty<Toast> toasts();

    Q_INVOKABLE void toast(const QString& title, const QString& message, const QString& icon = QString(),
        symmetria::Toast::Type type = Toast::Type::Info, int timeout = 5000,
        const QString& imagePath = QString(), const QString& key = QString(),
        QJSValue action = QJSValue());

signals:
    void toastsChanged();

private:
    QList<Toast*> m_toasts;
};

} // namespace symmetria
