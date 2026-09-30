"""Verify every packaged renderer resource against its generated manifest."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "asset-manifest.json").read_text())
assert {"index.html", "ThirdPartyNotices.txt", "dependency-licenses.json"} <= manifest.keys()
actual = {file.relative_to(root).as_posix() for file in root.rglob("*") if file.is_file() and file.name != "asset-manifest.json"}
assert actual == set(manifest), "Unexpected or missing renderer resources"
licenses = json.loads((root / "dependency-licenses.json").read_text())
allowed = {"MIT", "ISC", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "Python-2.0", "Unlicense"}
assert licenses and all(entry["selectedLicense"] in allowed for entry in licenses)
notices = (root / "ThirdPartyNotices.txt").read_text()
assert "Copyright (c) 2026 TABATA Hitoshi" in notices
assert "FluxMarkdown" not in notices

assert any(path.endswith(".woff2") for path in manifest)
assert any(path.endswith(".js") for path in manifest)
for relative, digest in manifest.items():
    file = (root / relative).resolve()
    assert file.is_relative_to(root.resolve()), relative
    assert hashlib.sha256(file.read_bytes()).hexdigest() == digest, relative
print(f"Verified {len(manifest)} Markdown resources")
