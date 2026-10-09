#include "cutils.hpp"

#include <QtConcurrent/qtconcurrentrun.h>
#include <QtQuick/qquickitemgrabresult.h>
#include <QtQuick/qquickwindow.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qfuturewatcher.h>
#include <qqmlengine.h>
#include <qtextcursor.h>
#include <qtextdocument.h>
#include <qtextobject.h>

namespace symmetria {

void CUtils::saveItem(QQuickItem* target, const QUrl& path) {
    this->saveItem(target, path, QRect(), QJSValue(), QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, const QRect& rect) {
    this->saveItem(target, path, rect, QJSValue(), QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, QJSValue onSaved) {
    this->saveItem(target, path, QRect(), onSaved, QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, QJSValue onSaved, QJSValue onFailed) {
    this->saveItem(target, path, QRect(), onSaved, onFailed);
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, const QRect& rect, QJSValue onSaved) {
    this->saveItem(target, path, rect, onSaved, QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, const QRect& rect, QJSValue onSaved, QJSValue onFailed) {
    if (!target) {
        qWarning() << "CUtils::saveItem: a target is required";
        return;
    }

    if (!path.isLocalFile()) {
        qWarning() << "CUtils::saveItem:" << path << "is not a local file";
        return;
    }

    if (!target->window()) {
        qWarning() << "CUtils::saveItem: unable to save target" << target << "without a window";
        return;
    }

    auto scaledRect = rect;
    const qreal scale = target->window()->devicePixelRatio();
    if (rect.isValid() && !qFuzzyCompare(scale + 1.0, 2.0)) {
        scaledRect =
            QRectF(rect.left() * scale, rect.top() * scale, rect.width() * scale, rect.height() * scale).toRect();
    }

    const QSharedPointer<const QQuickItemGrabResult> grabResult = target->grabToImage();

    QObject::connect(grabResult.data(), &QQuickItemGrabResult::ready, this,
        [grabResult, scaledRect, path, onSaved, onFailed, this]() {
            const auto future = QtConcurrent::run([=]() {
                QImage image = grabResult->image();

                if (scaledRect.isValid()) {
                    image = image.copy(scaledRect);
                }

                const QString file = path.toLocalFile();
                const QString parent = QFileInfo(file).absolutePath();
                return QDir().mkpath(parent) && image.save(file);
            });

            auto* watcher = new QFutureWatcher<bool>(this);
            auto* engine = qmlEngine(this);

            QObject::connect(watcher, &QFutureWatcher<bool>::finished, this, [=]() {
                if (watcher->result()) {
                    if (onSaved.isCallable()) {
                        onSaved.call(
                            { QJSValue(path.toLocalFile()), engine->toScriptValue(QVariant::fromValue(path)) });
                    }
                } else {
                    qWarning() << "CUtils::saveItem: failed to save" << path;
                    if (onFailed.isCallable()) {
                        onFailed.call({ engine->toScriptValue(QVariant::fromValue(path)) });
                    }
                }
                watcher->deleteLater();
            });
            watcher->setFuture(future);
        });
}

bool CUtils::copyFile(const QUrl& source, const QUrl& target, bool overwrite) const {
    if (!source.isLocalFile()) {
        qWarning() << "CUtils::copyFile: source" << source << "is not a local file";
        return false;
    }
    if (!target.isLocalFile()) {
        qWarning() << "CUtils::copyFile: target" << target << "is not a local file";
        return false;
    }

    if (overwrite) {
        if (!QFile::remove(target.toLocalFile())) {
            qWarning() << "CUtils::copyFile: overwrite was specified but failed to remove" << target.toLocalFile();
            return false;
        }
    }

    return QFile::copy(source.toLocalFile(), target.toLocalFile());
}

bool CUtils::deleteFile(const QUrl& path) const {
    if (!path.isLocalFile()) {
        qWarning() << "CUtils::deleteFile: path" << path << "is not a local file";
        return false;
    }

    return QFile::remove(path.toLocalFile());
}

QString CUtils::notificationBodyHtml(const QString& markdown, const QColor& linkColor, const QFont& font) const {
    if (markdown.isEmpty()) {
        return QString();
    }

    // Qt ignores Text.linkColor for MarkdownText. Keep Qt's Markdown parser,
    // then set the anchor foreground in the document before exporting HTML.
    QTextDocument document;
    document.setDefaultFont(font);
    document.setMarkdown(markdown);
    for (auto block = document.begin(); block.isValid(); block = block.next()) {
        for (auto fragmentIterator = block.begin(); !fragmentIterator.atEnd(); ++fragmentIterator) {
            const auto fragment = fragmentIterator.fragment();
            if (!fragment.isValid() || !fragment.charFormat().isAnchor()) {
                continue;
            }
            QTextCursor cursor(&document);
            cursor.setPosition(fragment.position());
            cursor.setPosition(fragment.position() + fragment.length(), QTextCursor::KeepAnchor);
            QTextCharFormat format;
            format.setForeground(linkColor);
            cursor.mergeCharFormat(format);
        }
    }
    return document.toHtml();
}

QString CUtils::toLocalFile(const QUrl& url) const {
    if (!url.isLocalFile()) {
        qWarning() << "CUtils::toLocalFile: given url is not a local file" << url;
        return QString();
    }

    return url.toLocalFile();
}

} // namespace symmetria
