from __future__ import annotations

import json
import os
from pathlib import Path
import tkinter as tk


SETTINGS_DIRECTORY = Path(
    os.environ.get("LOCALAPPDATA", str(Path.home()))
) / "A-C Script Studio"
SETTINGS_PATH = SETTINGS_DIRECTORY / "settings.json"


def load_settings() -> dict:
    try:
        value = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def save_settings(settings: dict) -> None:
    try:
        SETTINGS_DIRECTORY.mkdir(parents=True, exist_ok=True)
        temporary = SETTINGS_PATH.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(settings, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, SETTINGS_PATH)
    except OSError:
        pass


class EditorPreferencesMixin:
    def restore_preferences(self) -> None:
        if not os.environ.get("AC_GAME_PATH", "").strip():
            self.vars["game_path"].set(str(self.settings.get("gamePath", "")))

        geometry = str(self.settings.get("windowGeometry", ""))
        if geometry:
            try:
                self.geometry(geometry)
            except tk.TclError:
                pass

    def save_preferences(self) -> None:
        self.settings["gamePath"] = self.vars["game_path"].get().strip()
        if self.state() == "normal":
            self.settings["windowGeometry"] = self.geometry()
        save_settings(self.settings)

    def remember_project(self, path: Path) -> None:
        resolved = str(path.resolve())
        recent = [
            value for value in self.settings.get("recentProjects", [])
            if isinstance(value, str) and value.casefold() != resolved.casefold()
        ]
        self.settings["recentProjects"] = [resolved, *recent][:10]
        save_settings(self.settings)
        self.refresh_recent_menu()

    def refresh_recent_menu(self) -> None:
        if not hasattr(self, "recent_menu"):
            return
        self.recent_menu.delete(0, "end")
        recent = [
            Path(value) for value in self.settings.get("recentProjects", [])
            if isinstance(value, str) and Path(value).is_file()
        ]
        if not recent:
            self.recent_menu.add_command(label="No recent projects", state="disabled")
            return
        for path in recent:
            self.recent_menu.add_command(
                label=f"{path.name} — {path.parent}",
                command=lambda selected=path: self.open_recent_project(selected),
            )
        self.recent_menu.add_separator()
        self.recent_menu.add_command(label="Clear recent projects", command=self.clear_recent_projects)

    def open_recent_project(self, path: Path) -> None:
        if not path.is_file():
            self.settings["recentProjects"] = [
                value for value in self.settings.get("recentProjects", [])
                if str(value).casefold() != str(path).casefold()
            ]
            save_settings(self.settings)
            self.refresh_recent_menu()
            return
        if self.confirm_discard():
            self.open_path(path)

    def clear_recent_projects(self) -> None:
        self.settings["recentProjects"] = []
        save_settings(self.settings)
        self.refresh_recent_menu()
