import os
from pathlib import Path
from pathlib import PurePosixPath
import shutil
import zipfile


ZIP_PATH = Path(os.environ.get("WEB_ZIP", "/work/teaching-open-web-2.8.0.zip"))
OUTPUT_DIR = Path(os.environ.get("WEB_ROOT", "/work/output"))
OVERLAY_DIR = Path(os.environ["WEB_OVERLAY_DIR"]) if os.environ.get("WEB_OVERLAY_DIR") else None
INDEX_FILE = OUTPUT_DIR / "index.html"
ERRLOG = '<script async src=//api.paas.plus/js/errlog.js></script>'
PREVIEW_OLD = "window._CONFIG['onlinePreviewDomainURL'] = 'http://fileview.jeecg.com/onlinePreview'"
PREVIEW_NEW = "window._CONFIG['onlinePreviewDomainURL'] = window._CONFIG['webURL'] + '/preview/onlinePreview'"


def reset_output_dir() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for child in OUTPUT_DIR.iterdir():
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def resolve_member_path(name: str) -> Path:
    normalized = name.replace("\\", "/")
    parts = [part for part in PurePosixPath(normalized).parts if part not in ("", ".")]
    if any(part == ".." for part in parts):
        raise ValueError(f"unsafe zip member path: {name}")
    return OUTPUT_DIR.joinpath(*parts)


def extract_web() -> None:
    with zipfile.ZipFile(ZIP_PATH) as zf:
        for member in zf.infolist():
            if not member.filename:
                continue

            target = resolve_member_path(member.filename)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue

            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)


def apply_overlay() -> None:
    if OVERLAY_DIR is None or not OVERLAY_DIR.is_dir():
        return
    shutil.copytree(OVERLAY_DIR, OUTPUT_DIR, dirs_exist_ok=True)


def patch_index() -> None:
    text = INDEX_FILE.read_text(encoding="utf-8")
    text = text.replace(ERRLOG, "")
    text = text.replace(PREVIEW_OLD, PREVIEW_NEW)
    INDEX_FILE.write_text(text, encoding="utf-8")


def main() -> None:
    if not ZIP_PATH.exists():
        raise SystemExit(f"missing frontend package: {ZIP_PATH}")

    reset_output_dir()
    extract_web()
    apply_overlay()

    if not INDEX_FILE.exists():
        raise SystemExit(f"frontend extraction failed: {INDEX_FILE} not found")

    patch_index()
    print("web assets prepared")


if __name__ == "__main__":
    main()
