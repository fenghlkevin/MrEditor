"""Collect attribution and hash the generated offline renderer (standard library only)."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
web = root / "web-renderer"
assets = root / "Sources/MrEditorCore/Resources/MarkdownPreview"
notices = [(web / "UPSTREAM.md").read_text(), (web / "LICENSE").read_text()]
lock = json.loads((web / "package-lock.json").read_text())
for relative, metadata in sorted(lock["packages"].items()):
    if not relative or metadata.get("dev"):
        continue
    package = web / relative
    details = json.loads((package / "package.json").read_text())
    notices.append(f"\n\n{details.get('name', relative)} {details.get('version', '')}\nLicense: {metadata.get('license', 'See package license below')}\n")
    for file in sorted(package.iterdir()):
        if file.is_file() and file.name.lower().startswith(("license", "licence", "copying", "notice")):
            notices.append(file.read_text(errors="replace"))
(assets / "ThirdPartyNotices.txt").write_text("\n".join(notices))
manifest = {
    file.relative_to(assets).as_posix(): hashlib.sha256(file.read_bytes()).hexdigest()
    for file in sorted(assets.rglob("*"))
    if file.is_file() and file.name != "asset-manifest.json"
}
(assets / "asset-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Prepared {len(manifest)} Markdown resources with attribution and SHA-256 manifest")
