"""Verify every packaged renderer resource against its generated manifest."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "asset-manifest.json").read_text())
assert "index.html" in manifest and "ThirdPartyNotices.txt" in manifest
assert any(path.endswith(".woff2") for path in manifest)
assert any(path.endswith(".js") for path in manifest)
for relative, digest in manifest.items():
    file = (root / relative).resolve()
    assert file.is_relative_to(root.resolve()), relative
    assert hashlib.sha256(file.read_bytes()).hexdigest() == digest, relative
print(f"Verified {len(manifest)} Markdown resources")
