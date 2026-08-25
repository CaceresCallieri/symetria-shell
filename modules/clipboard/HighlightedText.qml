import qs.components
import qs.services
import QtQuick

// Text component that highlights search matches
StyledText {
    id: root

    required property string sourceText
    property string searchQuery: ""
    property color highlightColor: Colours.palette.m3primary

    // Cache escaped text for performance (only recomputed when sourceText changes)
    readonly property string escapedSource: escapeHtml(sourceText)

    // Use StyledText format for HTML-like highlighting
    textFormat: Text.StyledText

    // Build highlighted text with matched substrings wrapped in color tags
    text: {
        if (!searchQuery)
            return escapedSource;

        const query = searchQuery.toLowerCase();
        const source = sourceText;
        const sourceLower = source.toLowerCase();

        // Find all matches (case-insensitive)
        let result = "";
        let lastIndex = 0;
        let searchIndex = 0;

        while ((searchIndex = sourceLower.indexOf(query, lastIndex)) !== -1) {
            // Add text before match
            result += escapeHtml(source.substring(lastIndex, searchIndex));
            // Add highlighted match (preserve original case)
            const matchedText = source.substring(searchIndex, searchIndex + query.length);
            result += `<font color="${highlightColor}">${escapeHtml(matchedText)}</font>`;
            lastIndex = searchIndex + query.length;
        }

        // Add remaining text
        result += escapeHtml(source.substring(lastIndex));

        return result;
    }

    // Escape HTML special characters to prevent injection
    function escapeHtml(text: string): string {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
    }
}
