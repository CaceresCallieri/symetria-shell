#include "cutils.hpp"

#include <QGuiApplication>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextFrame>
#include <iostream>
#include <stdexcept>

namespace {
void require(bool condition, const char* message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

QTextCharFormat formatAt(QTextDocument& document, int position) {
    QTextCursor cursor(&document);
    cursor.setPosition(position);
    cursor.setPosition(position + 1, QTextCursor::KeepAnchor);
    return cursor.charFormat();
}

void verifyBody(const symmetria::CUtils& utils, const QString& markdown, const QColor& linkColor) {
    const QFont font("monospace", 13);
    QTextDocument original;
    original.setDefaultFont(font);
    original.setMarkdown(markdown);

    QTextDocument rendered;
    rendered.setHtml(utils.notificationBodyHtml(markdown, linkColor, font));
    require(rendered.toPlainText() == original.toPlainText(), "message text changed");
    require(rendered.rootFrame()->frameFormat().background().style() == Qt::NoBrush,
        "the exported body introduces a background");

    for (int position = 0; position < original.characterCount() - 1; ++position) {
        if (original.characterAt(position) == QChar::ParagraphSeparator) {
            continue;
        }
        const auto before = formatAt(original, position);
        const auto after = formatAt(rendered, position);
        require(before.isAnchor() == after.isAnchor(), "anchor membership changed");
        require(before.anchorHref() == after.anchorHref(), "link target changed");
        require(before.fontWeight() == after.fontWeight(), "bold formatting changed");
        require(before.fontItalic() == after.fontItalic(), "italic formatting changed");
        require(before.fontUnderline() == after.fontUnderline(), "underline formatting changed");
        if (before.isAnchor()) {
            require(after.foreground().color() == linkColor, "a link keeps the wrong foreground");
        } else {
            require(before.foreground() == after.foreground(), "non-link foreground changed");
        }
    }
}
} // namespace

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    try {
        const symmetria::CUtils utils;
        const QFont font("monospace", 13);
        require(utils.notificationBodyHtml("", QColor("#bdc2c7"), font).isEmpty(),
            "an empty body creates visible HTML");
        const QStringList bodies {
            "Keep <3 & > intact.",
            "**Meet** https://meet.google.com/rhy-zjiy-gpc?a=1&b=2\n\n[Second link](https://example.com/)",
            "[**bold** and *italic*](https://example.com/?a=1&b=2)",
            "[one](https://example.com/)[two](https://example.org/)",
            "[café 😊](https://example.com/#résumé) and plain Unicode: 日本語",
            "<span style=\"color:#ff0000\">red text</span> https://example.com/"
        };
        for (const auto& colour : {QColor("#bdc2c7"), QColor("#25d366")}) {
            for (const auto& body : bodies) {
                verifyBody(utils, body, colour);
            }
        }
        std::cout << "PASS notification links, formatting, literal text, theme colours, background, empty body\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
