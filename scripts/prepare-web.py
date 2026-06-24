from pathlib import Path
import shutil
import zipfile


ZIP_PATH = Path("/work/teaching-open-web-2.8.0.zip")
OUTPUT_DIR = Path("/work/output")
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


def extract_web() -> None:
    with zipfile.ZipFile(ZIP_PATH) as zf:
        zf.extractall(OUTPUT_DIR)


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

    if not INDEX_FILE.exists():
        raise SystemExit(f"frontend extraction failed: {INDEX_FILE} not found")

    patch_index()
    print("web assets prepared")


if __name__ == "__main__":
    main()
