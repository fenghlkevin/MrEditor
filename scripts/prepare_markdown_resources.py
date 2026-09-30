"""Collect complete runtime attributions, enforce reviewed licenses, hash assets."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
web = root / "web-renderer"
assets = root / "Sources/MrEditorCore/Resources/MarkdownPreview"
notices = ["TextStack document preview\n\n" + (root / "LICENSE").read_text()]
lock = json.loads((web / "package-lock.json").read_text())
allowed = {"MIT", "ISC", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "Python-2.0", "Unlicense"}
inventory = []
for relative, metadata in sorted(lock["packages"].items()):
    if not relative or metadata.get("dev"):
        continue
    package = web / relative
    details = json.loads((package / "package.json").read_text())
    name = details["name"]
    declared = metadata.get("license", details.get("license"))
    selected = "Apache-2.0" if name == "dompurify" and declared == "(MPL-2.0 OR Apache-2.0)" else declared
    # khroma 2.1.0 omits the SPDX field, but ships the full MIT grant.
    if name == "khroma" and details["version"] == "2.1.0" and selected is None:
        assert "The MIT License (MIT)" in (package / "license").read_text()
        selected = "MIT"
    assert selected in allowed, f"Unreviewed runtime license: {name} {selected}"
    texts = []
    for file in sorted(package.iterdir()):
        if file.is_file() and file.name.lower().startswith(("license", "licence", "copying", "notice", "unlicense")):
            if name == "dompurify" and file.name == "LICENSE-MPL":
                continue  # Apache option selected; keep its full LICENSE.
            texts.append(file.read_text(errors="replace"))
    if not texts:
        # Some packages publish their grant in README instead of a LICENSE file.
        for readme in sorted(package.glob("README*")):
            match = re.search(r"^## License\s*$", readme.read_text(), re.M | re.I)
            if match:
                texts.append(readme.read_text()[match.start():])
    assert texts and any(len(text) > 100 for text in texts), f"Missing license text: {name}"
    license_text = "\n".join(texts)
    notices.append(f"\n\n{name} {details['version']}\nLicense: {selected}\n\n{license_text}")
    inventory.append({"name": name, "version": details["version"], "path": relative,
                      "declaredLicense": declared, "selectedLicense": selected,
                      "licenseTextSHA256": hashlib.sha256(license_text.encode()).hexdigest()})
(assets / "ThirdPartyNotices.txt").write_text("\n".join(notices))
(assets / "dependency-licenses.json").write_text(json.dumps(inventory, indent=2) + "\n")
manifest = {
    file.relative_to(assets).as_posix(): hashlib.sha256(file.read_bytes()).hexdigest()
    for file in sorted(assets.rglob("*"))
    if file.is_file() and file.name != "asset-manifest.json"
}
(assets / "asset-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Prepared {len(manifest)} resources; verified {len(inventory)} runtime license entries")
