"""Build the installable addon ZIP: python3 tools/package.py."""

from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
addon = root / "FlareUI_Druid"
files = {path.relative_to(addon).as_posix(): path for path in addon.rglob("*") if path.is_file()}
for name in ("README.md", "CHANGELOG.md", "LICENSE", "LICENSES/FlareUI.txt"):
    files[name] = root / name

toc = (addon / "FlareUI_Druid.toc").read_text()
for entry in toc.splitlines():
    if entry and not entry.startswith("#"):
        assert entry in files, f"Missing addon file: {entry}"

output = root / "dist" / "FlareUI-Druid.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for name, path in sorted(files.items()):
        archive.write(path, "FlareUI_Druid/" + name)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
print(output)
