from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path, PurePosixPath


class GameDataError(RuntimeError):
    pass


def _cache_root() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    base = Path(local_app_data) if local_app_data else Path.home() / "AppData" / "Local"
    return base / "A-C Script Studio" / "game-cache"


def _cache_key(info_path: Path, body_path: Path) -> str:
    info_stat = info_path.stat()
    body_stat = body_path.stat()
    value = f"{info_path.resolve()}|{info_stat.st_size}|{info_stat.st_mtime_ns}|{body_stat.st_size}|{body_stat.st_mtime_ns}"
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:24]


def _safe_relative(name: str) -> Path:
    normalized = name.replace("\\", "/").lstrip("/")
    relative = PurePosixPath(normalized)
    if not normalized or relative.is_absolute() or any(part in {"", ".", ".."} for part in relative.parts):
        raise GameDataError(f"The game archive contains an unsafe path: {name}")
    return Path(*relative.parts)


def _run_decompiler(tool: Path, source: Path, output_root: Path) -> list[Path]:
    output_root.mkdir(parents=True, exist_ok=True)
    before = {path.resolve() for path in output_root.rglob("*") if path.is_file()}
    try:
        completed = subprocess.run(
            [str(tool), "-o", str(output_root), str(source)],
            capture_output=True,
            text=True,
            timeout=180,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise GameDataError(f"Could not run FreeMote PsbDecompile.exe:\n{exc}") from exc
    created = [path for path in output_root.rglob("*") if path.is_file() and path.resolve() not in before]
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "The extractor returned an error.").strip()
        raise GameDataError(f"FreeMote could not extract {source.name}:\n{detail}")
    return created


def _find_index_json(paths: list[Path], root: Path) -> Path | None:
    candidates = [path for path in paths if path.suffix.lower() == ".json"]
    for path in candidates:
        try:
            document = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if isinstance(document, dict) and isinstance(document.get("file_info"), dict):
            return path
    expected = root / "c0patch_info.psb.m.json"
    return expected if expected.is_file() else None


def _copy_archive_entry(body: Path, destination: Path, value: object) -> None:
    entry = list(value) if isinstance(value, (list, tuple)) else []
    if len(entry) < 2:
        raise GameDataError(f"Invalid archive index entry for {destination.name}")
    try:
        offset = int(entry[0])
        length = int(entry[1])
    except (TypeError, ValueError) as exc:
        raise GameDataError(f"Invalid archive offset for {destination.name}") from exc
    if offset < 0 or length < 0:
        raise GameDataError(f"Invalid archive range for {destination.name}")
    body_size = body.stat().st_size
    if offset + length > body_size:
        raise GameDataError(f"Archive entry exceeds c0patch_body.bin: {destination.name}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with body.open("rb") as source, destination.open("wb") as target:
        source.seek(offset)
        remaining = length
        while remaining:
            chunk = source.read(min(1024 * 1024, remaining))
            if not chunk:
                raise GameDataError(f"Unexpected end of c0patch_body.bin while reading {destination.name}")
            target.write(chunk)
            remaining -= len(chunk)


def _link_or_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        return
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def prepare_game_data(game_root: Path, psb_decompiler: Path, report=lambda _text: None) -> dict[str, Path]:
    windata = game_root / "windata"
    info_path = windata / "c0patch_info.psb.m"
    body_path = windata / "c0patch_body.bin"
    if not game_root.is_dir() or not windata.is_dir():
        raise GameDataError("The selected folder is not an ANONYMOUS;CODE installation with a windata folder.")
    if not info_path.is_file() or not body_path.is_file():
        raise GameDataError("The selected game does not contain the CoZ c0patch index/body files.")
    if not psb_decompiler.is_file():
        raise GameDataError(f"FreeMote PsbDecompile.exe was not found:\n{psb_decompiler}")

    cache = _cache_root() / _cache_key(info_path, body_path)
    extract_root = cache / "coz-extract"
    archive_root = extract_root / "c0patch"
    scenario_root = cache / "base-scenario-json"
    marker = cache / ".complete"
    if marker.is_file() and (scenario_root / "scenelist.scn.m.json").is_file():
        return {"cache_root": cache, "extract_root": extract_root, "scenario_root": scenario_root}

    cache.mkdir(parents=True, exist_ok=True)
    report("Reading the installed c0patch index…")
    index_output = cache / "index"
    created = _run_decompiler(psb_decompiler, info_path, index_output)
    index_json = _find_index_json(created, index_output)
    if index_json is None:
        raise GameDataError("FreeMote did not produce c0patch_info.psb.m.json with a file_info table.")
    try:
        manifest = json.loads(index_json.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GameDataError(f"Could not read the decompiled c0patch index:\n{exc}") from exc
    file_info = manifest.get("file_info") if isinstance(manifest, dict) else None
    if not isinstance(file_info, dict):
        raise GameDataError("The decompiled c0patch index has no file_info table.")

    extract_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(index_json, extract_root / "c0patch_info.psb.m.json")
    for candidate in index_json.parent.rglob("*.resx.json"):
        shutil.copy2(candidate, extract_root / candidate.name)
    _link_or_copy(body_path, extract_root / "c0patch_body.bin")

    scenario_entries = 0
    for name, value in file_info.items():
        relative = _safe_relative(str(name))
        if relative.parts and relative.parts[0].lower() == "scenario":
            _copy_archive_entry(body_path, archive_root / relative, value)
            scenario_entries += 1
    if scenario_entries == 0:
        raise GameDataError("The installed c0patch index contains no scenario entries.")

    scenario_root.mkdir(parents=True, exist_ok=True)
    report(f"Decompiling {scenario_entries:,} installed scenario entries…")
    for packed in sorted((archive_root / "scenario").glob("*.scn.m")):
        created = _run_decompiler(psb_decompiler, packed, scenario_root)
        target = scenario_root / f"{packed.name}.json"
        if not target.is_file():
            json_candidates = [path for path in created if path.suffix.lower() == ".json"]
            if json_candidates:
                shutil.copy2(json_candidates[0], target)
        if not target.is_file():
            raise GameDataError(f"FreeMote did not produce scenario JSON for {packed.name}.")
        resource = packed.with_name(f"{packed.name}.resx.json")
        if resource.is_file():
            shutil.copy2(resource, scenario_root / resource.name)

    marker.write_text("ready\n", encoding="utf-8")
    return {"cache_root": cache, "extract_root": extract_root, "scenario_root": scenario_root}
