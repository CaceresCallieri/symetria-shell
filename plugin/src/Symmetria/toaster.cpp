#include "toaster.hpp"

#include <qdebug.h>
#include <qlogging.h>
#include <qtimer.h>

namespace symmetria {

Toast::Toast(const QString& title, const QString& message, const QString& icon, Type type, int timeout,
    const QString& imagePath, QJSValue action, const QString& key, QObject* parent)
    : QObject(parent)
    , m_closed(false)
    , m_key(key)
    , m_title(title)
    , m_message(message)
    , m_icon(icon)
    , m_imagePath(imagePath)
    , m_action(std::move(action))
    , m_type(type)
    , m_timeout(timeout)
    , m_hasAction(m_action.isCallable()) {
    m_timer = new QTimer(this);
    m_timer->setSingleShot(true);
    QObject::connect(m_timer, &QTimer::timeout, this, &Toast::close);

    applyDefaults();
    if (m_timeout > 0) {
        m_timer->start(m_timeout);
    }
    // else: persistent toast (timeout < 0), no auto-close
}

void Toast::applyDefaults() {
    if (m_icon.isEmpty()) {
        switch (m_type) {
        case Type::Success:
            m_icon = "check_circle_unread";
            break;
        case Type::Warning:
            m_icon = "warning";
            break;
        case Type::Error:
            m_icon = "error";
            break;
        default:
            m_icon = "info";
            break;
        }
    }

    // timeout == 0 means "use type-based default"; timeout < 0 means "persistent"
    if (m_timeout == 0) {
        switch (m_type) {
        case Type::Warning:
            m_timeout = 7000;
            break;
        case Type::Error:
            m_timeout = 10000;
            break;
        default:
            m_timeout = 5000;
            break;
        }
    }
}

void Toast::update(const QString& title, const QString& message, const QString& icon, Type type, int timeout) {
    m_timeout = timeout;

    if (m_title != title) {
        m_title = title;
        emit titleChanged();
    }
    if (m_message != message) {
        m_message = message;
        emit messageChanged();
    }

    m_icon = icon; // Reset before applyDefaults so empty triggers default
    m_type = type;
    applyDefaults();

    // Always emit — applyDefaults may have resolved empty icon
    emit iconChanged();
    emit typeChanged();

    if (m_timeout > 0) {
        m_timer->start(m_timeout);
    } else {
        m_timer->stop();
    }
}

bool Toast::closed() const {
    return m_closed;
}

QString Toast::key() const {
    return m_key;
}

QString Toast::title() const {
    return m_title;
}

QString Toast::message() const {
    return m_message;
}

QString Toast::icon() const {
    return m_icon;
}

QString Toast::imagePath() const {
    return m_imagePath;
}

int Toast::timeout() const {
    return m_timeout;
}

Toast::Type Toast::type() const {
    return m_type;
}

bool Toast::hasAction() const {
    return m_hasAction;
}

void Toast::invokeAction() {
    if (m_hasAction) {
        m_action.call();
        close();
    }
    // If called without an action, do nothing — callers should check hasAction() first.
}

void Toast::close() {
    if (!m_closed) {
        m_closed = true;
        emit closedChanged();
    }

    if (m_locks.isEmpty()) {
        emit finishedClose();
    }
}

void Toast::lock(QObject* sender) {
    m_locks << sender;
    QObject::connect(sender, &QObject::destroyed, this, &Toast::unlock);
}

void Toast::unlock(QObject* sender) {
    if (m_locks.remove(sender) && m_closed) {
        close();
    }
}

Toaster::Toaster(QObject* parent)
    : QObject(parent) {}

QQmlListProperty<Toast> Toaster::toasts() {
    return QQmlListProperty<Toast>(this, &m_toasts);
}

void Toaster::toast(const QString& title, const QString& message, const QString& icon, Toast::Type type, int timeout,
    const QString& imagePath, const QString& key, QJSValue action) {
    // Update existing keyed toast if found
    if (!key.isEmpty()) {
        for (auto* existing : m_toasts) {
            if (!existing->closed() && existing->key() == key) {
                existing->update(title, message, icon, type, timeout);
                return;
            }
        }
    }

    auto* toast = new Toast(title, message, icon, type, timeout, imagePath, std::move(action), key, this);
    QObject::connect(toast, &Toast::finishedClose, this, [toast, this]() {
        if (m_toasts.removeOne(toast)) {
            emit toastsChanged();
            if (!toast->imagePath().isEmpty()) {
                QFile::remove(toast->imagePath());
            }
            toast->deleteLater();
        }
    });
    m_toasts.push_front(toast);
    emit toastsChanged();
}

} // namespace symmetria
