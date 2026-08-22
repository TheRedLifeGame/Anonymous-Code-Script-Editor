from __future__ import annotations

import json
import re
from pathlib import Path


CHARACTER_TRANSLATIONS = {
    "ポロン": "Pollon",
    "モモ": "Momo",
    "クロス": "Cross",
    "ウインド": "Wind",
    "オズ": "Oz",
    "ノンノ": "Nonno",
    "バンビ": "Banbi",
    "リコ": "Riko",
    "イロハ": "Iroha",
    "カオル": "Kaoru",
    "リディ": "Liddie",
    "ジュノ": "Juno",
    "アスマ": "Asuma",
    "ユアン": "Ewan",
    "グレアム": "Graham",
    "ダビデ": "David",
    "ロザリオ": "Rosario",
    "ローニン": "Ronin",
    "フェリーノ": "Felino",
    "ダブ": "Dub",
    "アンドゥ": "Ando",
    "ケント": "Kent",
    "俺": "Protagonist",
    "おっさん": "Old man",
    "鮫洲さん": "Mr. Samezu",
    "クマさん": "Mr. Kuma",
}


class AssetCatalog:
    def __init__(self, workspace_root: Path, scenario_root: Path, game_root: Path | None = None, extract_root: Path | None = None) -> None:
        self.workspace_root = workspace_root
        self.scenario_root = scenario_root
        self.game_root = game_root
        self.extract_root = extract_root
        self.items: list[tuple[str, str, str, str]] = []
        self.storages: list[str] = []
        self._labels: dict[str, list[str]] = {}
        self.native_scenes: list[tuple[str, str, str, int]] = []
        self.characters: list[tuple[str, tuple[str, ...], str]] = []
        self.speakers: list[str] = []
        self._scenario_cache: dict[str, dict] = {}

    @staticmethod
    def display_name(key: str) -> str:
        key = str(key)
        translation = CHARACTER_TRANSLATIONS.get(key)
        return f"{key} ({translation})" if translation else key

    @staticmethod
    def key_from_display(value: str) -> str:
        value = str(value).strip()
        for key, translation in CHARACTER_TRANSLATIONS.items():
            if value == f"{key} ({translation})":
                return key
        return value

    def scan(self, report) -> None:
        items: dict[tuple[str, str, str], tuple[str, str, str, str]] = {}
        scenario_files = sorted(p for p in self.scenario_root.glob("*.scn.m.json") if not p.name.endswith(".resx.json"))
        if not self.scenario_root.is_dir():
            report("No local scenario extraction found — native scene browsing will be empty until you provide one.")
        self.storages = [p.name.removesuffix(".scn.m.json") for p in scenario_files]
        bgm_pattern = re.compile(r'"filename"\s*:\s*"(bgm[A-Za-z0-9_]+)"', re.I)
        character_files: dict[str, set[str]] = {}
        character_scenes: dict[str, set[str]] = {}
        speaker_keys: set[str] = set()
        native_scenes: list[tuple[str, str, str, int]] = []
        report("Reading music references…")
        for path in scenario_files:
            try:
                raw = path.read_text(encoding="utf-8")
                for match in bgm_pattern.finditer(raw):
                    asset_id = match.group(1).lower()
                    items[("Music", asset_id, "")] = ("Music", asset_id, "Packed in game sound archive", "Native scenario reference")
                document = json.loads(raw)
                storage = path.name.removesuffix(".scn.m.json")
                for native in document.get("scenes", []):
                    label = str(native.get("label", ""))
                    if label:
                        native_scenes.append((storage, label, str(native.get("title", "") or label), len(native.get("texts", []))))

                def walk(node):
                    if isinstance(node, list):
                        if len(node) >= 2 and node[1] == "character":
                            character_id = str(node[0])
                            character_scenes.setdefault(character_id, set()).add(storage)
                            definition = node[2] if len(node) >= 3 and isinstance(node[2], dict) else {}
                            redraw = definition.get("redraw", {}) if isinstance(definition, dict) else {}
                            image_file = redraw.get("imageFile", {}) if isinstance(redraw, dict) else {}
                            if isinstance(image_file, dict) and image_file.get("file"):
                                character_files.setdefault(character_id, set()).add(str(image_file["file"]))
                        if node and node[0] == "startline":
                            for index, value in enumerate(node[:-1]):
                                if value == "name":
                                    speaker_keys.add(str(node[index + 1]))
                        for child in node:
                            walk(child)
                    elif isinstance(node, dict):
                        for child in node.values():
                            walk(child)

                walk(document)
            except (OSError, UnicodeError, json.JSONDecodeError):
                continue
        self.native_scenes = sorted(native_scenes, key=lambda item: (item[0].lower(), item[1].lower()))
        self.speakers = sorted({key for key in speaker_keys if key}, key=str.casefold)
        self.characters = sorted(
            ((character_id, tuple(sorted(character_files.get(character_id, set()))), f"Used in {len(character_scenes.get(character_id, set()))} native scenario file(s)") for character_id in set(character_files) | set(character_scenes)),
            key=lambda item: item[0].casefold(),
        )
        for character_id, files, details in self.characters:
            sprite_text = ", ".join(files) if files else "Packed character data"
            items[("Character", character_id, "", details)] = ("Character", character_id, "", f"{self.display_name(character_id)} — Sprites: {sprite_text}; {details}")

        report("Indexing installed and extracted media…")
        archive_root = (self.extract_root or (self.workspace_root / "coz-extract")) / "c0patch"
        roots = [archive_root, self.workspace_root / "assets"]
        if self.game_root:
            roots.append(self.game_root / "windata" / "movie")
        for root in roots:
            if not root.is_dir():
                continue
            for path in root.rglob("*"):
                if not path.is_file():
                    continue
                kind = self._classify(path)
                if not kind:
                    continue
                try:
                    if path.stat().st_size > 800_000_000:
                        continue
                except OSError:
                    continue
                asset_id = self._asset_id(path)
                location = str(path)
                items[(kind, asset_id, location)] = (kind, asset_id, location, str(path.relative_to(root)))
        self.items = sorted(items.values(), key=lambda item: (item[0], item[1].lower()))
        report(f"Ready — {len(self.items):,} assets indexed")

    def labels(self, storage: str) -> list[str]:
        if storage in self._labels:
            return self._labels[storage]
        path = self.scenario_root / f"{storage}.scn.m.json"
        labels: list[str] = []
        pattern = re.compile(r'"label"\s*:\s*"([^"]+)"')
        try:
            for line in path.open("r", encoding="utf-8"):
                labels.extend(match.group(1) for match in pattern.finditer(line))
        except (OSError, UnicodeError):
            pass
        self._labels[storage] = list(dict.fromkeys(labels))
        return self._labels[storage]

    def native_scene(self, storage: str, label: str) -> dict | None:
        document = self._scenario_cache.get(storage)
        if document is None:
            try:
                document = json.loads((self.scenario_root / f"{storage}.scn.m.json").read_text(encoding="utf-8"))
                self._scenario_cache[storage] = document
            except (OSError, UnicodeError, json.JSONDecodeError):
                return None
        return next((scene for scene in document.get("scenes", []) if scene.get("label") == label), None)

    @staticmethod
    def _asset_id(path: Path) -> str:
        name = path.name
        for suffix in (".psb.m", ".scn.m", ".mzv", ".mp4", ".webm", ".wav", ".ogg", ".mp3", ".png", ".jpg", ".jpeg"):
            if name.lower().endswith(suffix):
                return name[: -len(suffix)]
        return path.stem

    @staticmethod
    def _classify(path: Path) -> str | None:
        lowered = str(path).replace("/", "\\").lower()
        ext = path.suffix.lower()
        if "\\movie\\" in lowered or ext in {".mzv", ".mp4", ".webm", ".avi", ".mov"}:
            return "Video"
        if ext in {".wav", ".mp3", ".ogg", ".wma", ".flac", ".m4a"} or "\\sound\\" in lowered:
            return "Audio"
        if "\\image\\" in lowered or ext in {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp"}:
            return "Image"
        if "\\motion\\" in lowered:
            return "Motion"
        if "\\scenario\\" in lowered:
            return "Scenario"
        return None
