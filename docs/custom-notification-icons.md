# Custom Notification Icons (Transparent Background)

Notifications can display custom icons with transparent backgrounds (e.g., SVG logos) instead of the default colored circular background.

## Usage

```bash
notify-send --app-name="My App" --icon="/path/to/icon.svg" "Title" "Message"
```

## How it Works

The freedesktop notification spec sends absolute icon paths via the `image-path` hint, not the `appIcon` property. Quickshell's built-in `appIcon` only handles icon theme names (like "firefox").

| Icon Type | Example | Background | Rendering |
|-----------|---------|------------|-----------|
| System icon | `--icon="firefox"` | Colored circle (m3secondaryContainer) | `ColouredIcon` via icon theme |
| Custom path | `--icon="/path/icon.svg"` | Transparent | Plain `Image` component |

## Technical Details

### 1. Hint Extraction (`services/Notifs.qml`)

- Checks `notification.hints["image-path"]` for absolute file paths
- Validates extension against whitelist: `.svg`, `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`
- Falls back to `notification.appIcon` for theme icon names

```qml
// Validate that a path has a supported image extension
function isValidImagePath(path) {
    if (!path) return false;
    const validExts = [".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif"];
    const lower = path.toLowerCase().split('?')[0].split('#')[0];  // Strip query params
    return validExts.some(ext => lower.endsWith(ext));
}

// In Component.onCompleted:
const imagePath = notification.hints["image-path"] ?? "";
const validPath = imagePath && isValidImagePath(imagePath);
appIcon = validPath ? imagePath : notification.appIcon;
```

### 2. Transparency Detection (`modules/notifications/Notification.qml`)

- `hasTransparentIcon` property detects paths starting with `/`, `file://`, or `~/`
- When true: uses plain `Image` component (preserves SVG alpha channel)
- When false: uses `ColouredIcon` with icon theme engine

```qml
readonly property bool hasTransparentIcon: {
    const icon = modelData.appIcon;
    return icon.startsWith("/") ||
           icon.startsWith("file://") ||
           icon.startsWith("~/");
}
```

### 3. Duplicate Prevention

- When `image-path` is used as `appIcon`, the `image` property is cleared
- Prevents the same icon appearing twice (once as app icon, once as notification image)

```qml
// Don't use notification.image if we're using image-path as appIcon
image = validPath ? "" : notification.image;
```

## Why Plain Image vs IconImage

Qt's `IconImage`/icon theme engine renders SVGs onto a pre-initialized pixmap that may have a white background. Qt's plain `Image` component uses a different rendering path that preserves transparency.

This is a known Qt behavior - the icon theme engine (`QSvgIconEngine`) initializes the render target differently than direct SVG rendering.

## Supported Path Formats

| Format | Example | Notes |
|--------|---------|-------|
| Absolute path | `/home/user/icon.svg` | Most common |
| File URL | `file:///home/user/icon.svg` | Supported |
| Home-relative | `~/icons/icon.svg` | Supported |
| With query params | `/path/icon.svg?v=123` | Params stripped for validation |

## Files Modified

| File | Purpose |
|------|---------|
| `services/Notifs.qml` | Hint extraction, validation, duplicate prevention |
| `modules/notifications/Notification.qml` | Rendering logic, transparency detection |

## Testing

```bash
# Custom SVG icon (should be transparent)
notify-send --app-name="Claude Code" --icon="/home/jc/scripts/claude-icon.svg" "Test" "Transparent background"

# System icon (should have colored background)
notify-send --app-name="Firefox" --icon="firefox" "Test" "Colored background"

# File URL format
notify-send --icon="file:///home/jc/scripts/claude-icon.svg" "Test" "File URL"
```

## Related Resources

- [Desktop Notifications Specification](https://specifications.freedesktop.org/notification-spec/latest/)
- [Qt Forum: SVG transparent background issues](https://forum.qt.io/topic/14762/solved-problem-with-svg-pictures-and-transparent-background)
- [Quickshell Notification Documentation](https://quickshell.org/docs/v0.2.1/types/Quickshell.Services.Notifications/Notification/)
