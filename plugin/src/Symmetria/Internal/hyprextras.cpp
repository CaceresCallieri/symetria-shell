#include "hyprextras.hpp"

#include <qdir.h>
#include <qjsonarray.h>
#include <qlocalsocket.h>
#include <qvariant.h>

namespace symmetria::internal::hypr {

namespace {

// Hyprland answers "ok" to a request that worked. A Lua error in `eval` or
// `dispatch` comes back as text on a socket that worked, so a connection
// success alone hides it. Hyprland 0.57 made that the common failure: every
// hyprlang-era request turned into a Lua syntax error.
bool isHyprlandOk(const QByteArray& response) {
    return response.trimmed() == "ok";
}

QString luaStringLiteral(const QString& value) {
    QString escaped;
    escaped.reserve(value.size() + 2);
    for (const auto character : value) {
        if (character == '\\' || character == '"') {
            escaped += '\\';
            escaped += character;
        } else if (character.unicode() < 0x20 || character.unicode() == 0x7f) {
            escaped += QString("\\%1").arg(static_cast<int>(character.unicode()), 3, 10, QChar(u'0'));
        } else {
            escaped += character;
        }
    }
    return '"' + escaped + '"';
}

// Lua literal for one option value. Hyprland 0.57's typed config rejects 0/1
// for a boolean option, so callers pass real booleans for those.
QString luaValueLiteral(const QVariant& value) {
    switch (value.typeId()) {
        case QMetaType::Bool:
            return value.toBool() ? "true" : "false";
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::LongLong:
        case QMetaType::ULongLong:
        case QMetaType::Double:
        case QMetaType::Float:
            return value.toString();
        default:
            return luaStringLiteral(value.toString());
    }
}

// `hl.config({ general = { gaps_in = 0 } })` for the option "general:gaps_in".
QString luaConfigCall(const QString& option, const QVariant& value) {
    const auto path = option.split(':');
    auto table = luaValueLiteral(value);
    for (auto index = path.size(); index-- > 0;) {
        table = QString("{ %1 = %2 }").arg(path.at(index), table);
    }
    return QString("hl.config(%1)").arg(table);
}

} // namespace

HyprExtras::HyprExtras(QObject* parent)
    : QObject(parent)
    , m_requestSocket("")
    , m_eventSocket("")
    , m_socket(nullptr)
    , m_socketValid(false)
    , m_devices(new HyprDevices(this)) {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        qWarning()
            << "HyprExtras::HyprExtras: $HYPRLAND_INSTANCE_SIGNATURE is unset. Unable to connect to Hyprland socket.";
        return;
    }

    auto hyprDir = QString("%1/hypr/%2").arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = "/tmp/hypr/" + his;

        if (!QDir(hyprDir).exists()) {
            qWarning() << "HyprExtras::HyprExtras: Hyprland socket directory does not exist. Unable to connect to "
                          "Hyprland socket.";
            return;
        }
    }

    m_requestSocket = hyprDir + "/.socket.sock";
    m_eventSocket = hyprDir + "/.socket2.sock";

    refreshOptions();
    refreshDevices();

    m_socket = new QLocalSocket(this);

    QObject::connect(m_socket, &QLocalSocket::errorOccurred, this, &HyprExtras::socketError);
    QObject::connect(m_socket, &QLocalSocket::stateChanged, this, &HyprExtras::socketStateChanged);
    QObject::connect(m_socket, &QLocalSocket::readyRead, this, &HyprExtras::readEvent);

    m_socket->connectToServer(m_eventSocket, QLocalSocket::ReadOnly);
}

QVariantHash HyprExtras::options() const {
    return m_options;
}

HyprDevices* HyprExtras::devices() const {
    return m_devices;
}

void HyprExtras::message(const QString& message) {
    if (message.isEmpty()) {
        return;
    }

    makeRequest(message, [message](bool success, const QByteArray& res) {
        if (!success || !isHyprlandOk(res)) {
            qWarning() << "HyprExtras::message: Hyprland rejected" << message << "->" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::batchMessage(const QStringList& messages) {
    if (messages.isEmpty()) {
        return;
    }

    makeRequest("[[BATCH]]" + messages.join(";"), [](bool success, const QByteArray& res) {
        if (!success) {
            qWarning() << "HyprExtras::batchMessage: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::applyOptions(const QVariantHash& options) {
    if (options.isEmpty()) {
        return;
    }

    // Hyprland 0.57 removed `keyword`; options are set through Lua `hl.config`.
    // One `eval` carries every call: Lua needs no separator between statements,
    // and `[[BATCH]]` would split a Lua string on its `;`.
    QStringList configCalls;
    for (auto it = options.constBegin(); it != options.constEnd(); ++it) {
        configCalls << luaConfigCall(it.key(), it.value());
    }
    const auto request = "eval " + configCalls.join(' ');

    makeRequest(request, [this, request](bool success, const QByteArray& res) {
        if (!success || !isHyprlandOk(res)) {
            qWarning() << "HyprExtras::applyOptions: Hyprland rejected" << request << "->" << QString::fromUtf8(res);
        }
        refreshOptions();
    });
}

void HyprExtras::refreshOptions() {
    if (!m_optionsRefresh.isNull()) {
        m_optionsRefresh->close();
    }

    m_optionsRefresh = makeRequestJson("descriptions", [this](bool success, const QJsonDocument& response) {
        m_optionsRefresh.reset();
        if (!success) {
            return;
        }

        const auto options = response.array();
        bool dirty = false;

        for (const auto& o : std::as_const(options)) {
            const auto obj = o.toObject();
            // Hyprland 0.57 shape: { "name": "general:gaps_in", "current": ... }.
            const auto key = obj.value("name").toString();
            const auto value = obj.value("current").toVariant();
            if (m_options.value(key) != value) {
                dirty = true;
                m_options.insert(key, value);
            }
        }

        if (dirty) {
            emit optionsChanged();
        }
    });
}

void HyprExtras::refreshDevices() {
    if (!m_devicesRefresh.isNull()) {
        m_devicesRefresh->close();
    }

    m_devicesRefresh = makeRequestJson("devices", [this](bool success, const QJsonDocument& response) {
        m_devicesRefresh.reset();
        if (success) {
            m_devices->updateLastIpcObject(response.object());
        }
    });
}

void HyprExtras::socketError(QLocalSocket::LocalSocketError error) const {
    if (!m_socketValid) {
        qWarning() << "HyprExtras::socketError: unable to connect to Hyprland event socket:" << error;
    } else {
        qWarning() << "HyprExtras::socketError: Hyprland event socket error:" << error;
    }
}

void HyprExtras::socketStateChanged(QLocalSocket::LocalSocketState state) {
    if (state == QLocalSocket::UnconnectedState && m_socketValid) {
        qWarning() << "HyprExtras::socketStateChanged: Hyprland event socket disconnected.";
    }

    m_socketValid = state == QLocalSocket::ConnectedState;
}

void HyprExtras::readEvent() {
    while (true) {
        auto rawEvent = m_socket->readLine();
        if (rawEvent.isEmpty()) {
            break;
        }
        rawEvent.truncate(rawEvent.length() - 1); // Remove trailing \n
        const auto event = QByteArrayView(rawEvent.data(), rawEvent.indexOf(">>"));
        handleEvent(QString::fromUtf8(event));
    }
}

void HyprExtras::handleEvent(const QString& event) {
    if (event == "configreloaded") {
        refreshOptions();
    } else if (event == "activelayout") {
        refreshDevices();
    }
}

HyprExtras::SocketPtr HyprExtras::makeRequestJson(
    const QString& request, const std::function<void(bool, QJsonDocument)>& callback) {
    return makeRequest("j/" + request, [callback](bool success, const QByteArray& response) {
        callback(success, QJsonDocument::fromJson(response));
    });
}

HyprExtras::SocketPtr HyprExtras::makeRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return SocketPtr();
    }

    auto socket = SocketPtr::create(this);

    QObject::connect(socket.data(), &QLocalSocket::connected, this, [=, this]() {
        QObject::connect(socket.data(), &QLocalSocket::readyRead, this, [socket, callback]() {
            const auto response = socket->readAll();
            callback(true, std::move(response));
            socket->close();
        });

        socket->write(request.toUtf8());
        socket->flush();
    });

    QObject::connect(socket.data(), &QLocalSocket::errorOccurred, this, [=](QLocalSocket::LocalSocketError err) {
        qWarning() << "HyprExtras::makeRequest: error making request:" << err << "| request:" << request;
        callback(false, {});
        socket->close();
    });

    socket->connectToServer(m_requestSocket);

    return socket;
}

} // namespace symmetria::internal::hypr
