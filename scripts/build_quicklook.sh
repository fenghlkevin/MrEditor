#!/bin/sh
# Build an app-extension executable using Apple's NSExtensionMain entry point.
# No separate Xcode project or third-party build tool is needed.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
BIN="$2"
PREVIEW="$APP/Contents/PlugIns/MrEditorQuickLook.appex"
QUICKLOOK_BUILD="$ROOT/.build/quicklook"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
mkdir -p "$PREVIEW/Contents/MacOS" "$PREVIEW/Contents/Resources" "$QUICKLOOK_BUILD"

for ARCH in $(lipo -archs "$BIN"); do
    xcrun swiftc -O -swift-version 5 -parse-as-library -application-extension \
        -module-name MrEditorQuickLook -target "$ARCH-apple-macos13.0" -sdk "$SDK" \
        -framework AppKit -framework WebKit -framework QuickLookUI \
        -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -application_extension \
        "$ROOT/Sources/MrEditorQuickLook/PreviewViewController.swift" \
        "$ROOT/Sources/MrEditorCore/UI/MarkdownPreviewResources.swift" \
        "$ROOT/Sources/MrEditorCore/UI/MarkdownAssetHandler.swift" \
        "$ROOT/Sources/MrEditorCore/Core/QuickLookMarkdownDocument.swift" \
        "$ROOT/Sources/MrEditorCore/Core/DocumentPreviewFormat.swift" \
        -o "$QUICKLOOK_BUILD/MrEditorQuickLook-$ARCH"
done
set --
for ARCH in $(lipo -archs "$BIN"); do
    set -- "$@" "$QUICKLOOK_BUILD/MrEditorQuickLook-$ARCH"
done
lipo -create "$@" -output "$PREVIEW/Contents/MacOS/MrEditorQuickLook"
cp -R "$ROOT/Sources/MrEditorCore/Resources/MarkdownPreview" "$PREVIEW/Contents/Resources/"
python3 "$ROOT/scripts/configure_quicklook.py" "$APP"
python3 "$ROOT/scripts/verify_markdown_resources.py" "$PREVIEW/Contents/Resources/MarkdownPreview"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - --entitlements "$ROOT/Sources/MrEditorQuickLook/MrEditorQuickLook.entitlements" "$PREVIEW"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        --entitlements "$ROOT/Sources/MrEditorQuickLook/MrEditorQuickLook.entitlements" "$PREVIEW"
fi
codesign --verify --strict "$PREVIEW"
