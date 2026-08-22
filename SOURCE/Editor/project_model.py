from __future__ import annotations

import re

DEFAULT_HASH = "dab8b2d721f84912083080dca0aeef59"


def new_project() -> dict:
    return {
        "schemaVersion": 2,
        "metadata": {"title": "MY ANONYMOUS;CODE STORY", "version": "0.1.0", "continuity": "Custom scene project"},
        "voiceCharacters": ["ポロン", "モモ", "クロス", "ウインド"],
        "launchAlias": {"storage": "ac_00_01.ks", "sourceScene": "ac_ex_scene_01", "internalHash": DEFAULT_HASH},
        "scenes": [{
            "id": "ac_ex_scene_01", "title": "MY FIRST SCENE",
            "template": {"storage": "ac_03_20.ks", "target": "*flashback_1", "mode": "blank"},
            "presentation": {"background": "acb_0000n", "music": "bgm04", "hideUnlisted": False, "speakerFocus": False},
            "next": None, "pages": [{"speaker": "", "text": "Write your first line here."}],
        }],
        "injections": [],
    }


def ensure_project(project: dict) -> dict:
    project.setdefault("schemaVersion", 2)
    project.setdefault("metadata", {}).setdefault("title", "")
    project["metadata"].setdefault("version", "")
    project.setdefault("voiceCharacters", [])
    project.setdefault("launchAlias", {"storage": "ac_00_01.ks", "sourceScene": "", "internalHash": DEFAULT_HASH})
    project.setdefault("scenes", [])
    project.setdefault("injections", [])
    for scene in project["scenes"]:
        scene.setdefault("template", {"storage": "", "target": "*start", "mode": "blank"})
        scene.setdefault("pages", [])
        scene.setdefault("next", None)
    return project


def normalize_edge(edge: dict | None) -> None:
    if edge is None:
        return
    target = str(edge.get("target", "")).strip()
    edge["target"] = target if target.startswith("*") else "*" + (target or "start")


def validate_project(project: dict) -> list[str]:
    errors: list[str] = []
    if project.get("schemaVersion") != 2:
        errors.append("schemaVersion must be 2.")
    if not str(project.get("metadata", {}).get("title", "")).strip():
        errors.append("Project title is required.")
    scenes = project.get("scenes", [])
    if not scenes:
        errors.append("At least one scene is required.")
    ids: set[str] = set()
    for scene in scenes:
        scene_id = str(scene.get("id", ""))
        prefix = scene_id or "Unnamed scene"
        if not re.fullmatch(r"[A-Za-z0-9_]+", scene_id):
            errors.append(f"{prefix}: id must use only ASCII letters, numbers, and underscores.")
        if scene_id in ids:
            errors.append(f"Duplicate scene id: {scene_id}.")
        ids.add(scene_id)
        if not str(scene.get("title", "")).strip():
            errors.append(f"{prefix}: title is required.")
        _validate_edge(scene.get("template"), f"{prefix} template", errors)
        pages = scene.get("pages", [])
        if not pages:
            errors.append(f"{prefix}: add at least one dialogue page.")
        for index, page in enumerate(pages, 1):
            if not str(page.get("text", "")).strip():
                errors.append(f"{prefix}, page {index}: text is required.")
            if page.get("window") not in (None, "", "dialogue", "narration"):
                errors.append(f"{prefix}, page {index}: window must be dialogue or narration.")
        if scene.get("next") is not None:
            _validate_edge(scene["next"], f"{prefix} next branch", errors)
        music = str(scene.get("presentation", {}).get("music", ""))
        if music and not re.fullmatch(r"[A-Za-z0-9_]+", music):
            errors.append(f"{prefix}: music id contains invalid characters.")
    if project.get("launchAlias", {}).get("sourceScene") not in ids:
        errors.append("GAME START scene must reference an existing scene id.")
    injection_ids: set[str] = set()
    for injection in project.get("injections", []):
        ident = str(injection.get("id", ""))
        if not ident:
            errors.append("Every injection needs an id.")
        elif ident in injection_ids:
            errors.append(f"Duplicate injection id: {ident}.")
        injection_ids.add(ident)
        kind = injection.get("kind")
        if kind not in ("edge", "afterLine"):
            errors.append(f"{ident}: kind must be edge or afterLine.")
        _validate_edge(injection.get("source"), f"{ident} source", errors)
        _validate_edge(injection.get("expectedNext"), f"{ident} expected next", errors)
        _validate_edge(injection.get("destination"), f"{ident} destination", errors)
        if kind == "afterLine":
            if not str(injection.get("line", {}).get("text", "")).strip():
                errors.append(f"{ident}: after-line text is required.")
            if not str(injection.get("resumeTarget", "")).startswith("*"):
                errors.append(f"{ident}: resume target must begin with *.")
    return errors


def _validate_edge(edge: object, name: str, errors: list[str]) -> None:
    if not isinstance(edge, dict):
        errors.append(f"{name}: edge is missing.")
        return
    if not str(edge.get("storage", "")).lower().endswith(".ks"):
        errors.append(f"{name}: storage must end with .ks.")
    if not str(edge.get("target", "")).startswith("*"):
        errors.append(f"{name}: target must begin with *.")
