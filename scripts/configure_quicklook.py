"""Declare the embedded Markdown preview extension and shared file type."""
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
parent_file = app / "Contents/Info.plist"
with parent_file.open("rb") as file:
    parent = plistlib.load(file)
types = ["net.daringfireball.markdown", "public.json", "public.yaml", "public.comma-separated-values-text", "public.tab-separated-values-text", "public.source-code", "public.script", "public.plain-text", "public.xml", "public.html", "public.svg-image"]
# Register concrete source types as well as their supertypes: Quick Look can
# prefer a built-in provider registered for the concrete type.
types += ["com.netscape.javascript-source", "public.jsx-source", "public.typescript",
          "public.python-script", "public.shell-script", "public.bash-script", "public.zsh-script",
          "org.iso.sql", "public.swift-source", "com.sun.java-source", "org.kotlinlang.source",
          "public.c-source", "public.c-header", "public.c-plus-plus-source", "public.c-plus-plus-header",
          "com.microsoft.c-sharp", "org.golang.golang", "org.rust-lang.rust", "public.ruby-script",
          "public.php-script", "public.lua-source", "public.perl-script", "dev.dart.dart", "public.css",
          "com.sass-lang.scss", "com.apple.property-list", "public.toml", "com.microsoft.ini",
          "com.apple.log", "public.patch-file", "org.vuejs.source", "public.ndjson"]
parent["UTImportedTypeDeclarations"] = [{
    "UTTypeIdentifier": types[0], "UTTypeDescription": "Markdown document",
    "UTTypeConformsTo": ["public.plain-text"],
    "UTTypeTagSpecification": {"public.filename-extension": ["md", "markdown"], "public.mime-type": "text/markdown"},
}]
for identifier, extensions in [("com.aaedit.mermaid", ["mmd", "mermaid"]), ("com.aaedit.yaml", ["yaml", "yml"]), ("com.aaedit.configuration", ["toml", "ini", "conf", "cfg", "properties", "env", "log", "out", "jsonl", "ndjson"])]:
    types.append(identifier)
    parent["UTImportedTypeDeclarations"].append({"UTTypeIdentifier": identifier, "UTTypeConformsTo": ["public.plain-text"], "UTTypeTagSpecification": {"public.filename-extension": extensions}})
parent["CFBundleDocumentTypes"].insert(0, {
    "CFBundleTypeName": "Markdown document", "CFBundleTypeRole": "Editor",
    "LSHandlerRank": "Alternate", "LSItemContentTypes": types,
})
with parent_file.open("wb") as file:
    plistlib.dump(parent, file)
extension = {
    "CFBundleIdentifier": parent["CFBundleIdentifier"] + ".QuickLook",
    "CFBundleDisplayName": parent["CFBundleDisplayName"] + " Preview",
    "CFBundleName": "MrEditorQuickLook", "CFBundleExecutable": "MrEditorQuickLook",
    "CFBundlePackageType": "XPC!", "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleVersion": parent["CFBundleVersion"],
    "CFBundleShortVersionString": parent["CFBundleShortVersionString"],
    "LSMinimumSystemVersion": "13.0",
    "NSExtension": {
        "NSExtensionPointIdentifier": "com.apple.quicklook.preview",
        "NSExtensionPrincipalClass": "MrEditorQuickLookController",
        "NSExtensionAttributes": {"QLSupportedContentTypes": types, "QLSupportsSearchableItems": False, "QLIsDataBasedPreview": False},
    },
}
with (app / "Contents/PlugIns/MrEditorQuickLook.appex/Contents/Info.plist").open("wb") as file:
    plistlib.dump(extension, file)
