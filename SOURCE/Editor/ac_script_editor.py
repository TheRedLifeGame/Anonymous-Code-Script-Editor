#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

if __package__:
    from .asset_catalog import AssetCatalog
    from .editor_assets import AssetEditorMixin
    from .editor_controller import EditorControllerMixin
    from .editor_navigation import EditorNavigationMixin
    from .editor_preferences import EditorPreferencesMixin, load_settings
    from .editor_views import EditorViewMixin
    from .project_model import ensure_project, new_project, validate_project
else:
    from asset_catalog import AssetCatalog
    from editor_assets import AssetEditorMixin
    from editor_controller import EditorControllerMixin
    from editor_navigation import EditorNavigationMixin
    from editor_preferences import EditorPreferencesMixin, load_settings
    from editor_views import EditorViewMixin
    from project_model import ensure_project, new_project, validate_project


if getattr(sys, "frozen", False):
    WORKSPACE_ROOT = Path(sys.executable).resolve().parent
    BUNDLE_ROOT = Path(sys._MEIPASS).resolve()
    SOURCE_ROOT = BUNDLE_ROOT / "SOURCE"
else:
    SOURCE_ROOT = Path(__file__).resolve().parent.parent
    WORKSPACE_ROOT = SOURCE_ROOT.parent
    BUNDLE_ROOT = WORKSPACE_ROOT
PROJECT_ROOT = WORKSPACE_ROOT if getattr(sys, "frozen", False) else SOURCE_ROOT
SCENARIO_ROOT = WORKSPACE_ROOT / "base-scenario-json"
class ACEditor(
    EditorViewMixin,
    EditorControllerMixin,
    AssetEditorMixin,
    EditorNavigationMixin,
    EditorPreferencesMixin,
    tk.Tk,
):
    BG = "#f5f7fb"
    PANEL = "#ffffff"
    INPUT = "#ffffff"
    TEXT = "#1f2937"
    MUTED = "#667085"
    ACCENT = "#1264a3"
    BORDER = "#d9e1ec"
    SELECT = "#dceeff"

    def __init__(self, initial_path: str | None) -> None:
        super().__init__()
        self.title("A;C Script Studio")
        self.geometry("1480x900")
        self.minsize(1080, 700)
        self.configure(bg=self.BG)
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.project = new_project()
        self.project_path: Path | None = None
        self.dirty = False
        self.loading = False
        self.scene_index: int | None = None
        self.page_index: int | None = None
        self.injection_index: int | None = None
        self.catalog = AssetCatalog(WORKSPACE_ROOT, SCENARIO_ROOT)
        self.assets: list[tuple[str, str, str, str]] = []
        self.worker_messages: queue.Queue = queue.Queue()
        self.settings = load_settings()
        self._configure_style()
        self._create_variables()
        self.restore_preferences()
        self._build_ui()
        self._wire_traces()
        self._wire_shortcuts()
        default_project = PROJECT_ROOT / "project.json"
        if not default_project.is_file():
            default_project = SOURCE_ROOT / "project.json"
        path = Path(initial_path).resolve() if initial_path else default_project
        self.open_path(path) if path.is_file() else self.set_project(new_project(), None)
        self.after(120, self.start_asset_scan)

    def _build_branches_tab(self) -> None:
        page = self._tab("Story branches")
        split = ttk.Panedwindow(page, orient=tk.HORIZONTAL)
        split.pack(fill=tk.BOTH, expand=True)
        left = ttk.Frame(split, padding=6)
        right = self._form(split)
        split.add(left, weight=1)
        split.add(right, weight=3)
        self.injection_list = tk.Listbox(left, width=34, bg="#ffffff", fg=self.TEXT, selectbackground=self.SELECT, selectforeground=self.TEXT, relief=tk.FLAT, activestyle="none", highlightthickness=1, highlightbackground=self.BORDER)
        self.injection_list.pack(fill=tk.BOTH, expand=True)
        self.injection_list.bind("<<ListboxSelect>>", self.select_injection)
        buttons = ttk.Frame(left)
        buttons.pack(fill=tk.X, pady=(8, 0))
        ttk.Button(buttons, text="+ Edge", command=lambda: self.add_injection("edge")).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(buttons, text="+ After line", command=lambda: self.add_injection("afterLine")).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(buttons, text="Remove", command=self.remove_injection).pack(side=tk.LEFT)
        self.injection_widgets: list[tk.Widget] = []
        row = 0
        for label, name, values in (
            ("Kind", "injection_kind", ("edge", "afterLine")),
            ("Injection id", "injection_id", None),
            ("Source storage", "source_storage", None),
            ("Source label", "source_target", None),
            ("Expected next storage", "expected_storage", None),
            ("Expected next label", "expected_target", None),
        ):
            widget = ttk.Combobox(right, textvariable=self.vars[name], values=values, state="readonly" if values else "normal") if values else ttk.Entry(right, textvariable=self.vars[name])
            self.injection_widgets.append(widget)
            row = self._row(right, row, label, widget)
        self.destination_combo = ttk.Combobox(right, textvariable=self.vars["destination_scene"], state="readonly")
        self.injection_widgets.append(self.destination_combo)
        row = self._row(right, row, "Destination scene", self.destination_combo)
        self.line_speaker_entry = ttk.Entry(right, textvariable=self.vars["line_speaker"])
        self.injection_widgets.append(self.line_speaker_entry)
        row = self._row(right, row, "Exact line speaker", self.line_speaker_entry)
        self.line_text = tk.Text(right, height=5, wrap=tk.WORD, bg=self.INPUT, fg=self.TEXT, insertbackground=self.TEXT, relief=tk.SOLID, borderwidth=1, highlightthickness=0, padx=7, pady=7)
        self.line_text.bind("<FocusOut>", lambda _: self.commit_injection())
        self.injection_widgets.append(self.line_text)
        row = self._row(right, row, "Exact line text", self.line_text)
        self.resume_entry = ttk.Entry(right, textvariable=self.vars["resume_target"])
        self.injection_widgets.append(self.resume_entry)
        self._row(right, row, "Generated resume label", self.resume_entry, "After-line branches return here. Start it with * and keep it unique.")

    def _build_assets_tab(self) -> None:
        page = self._tab("Assets & media")
        top = ttk.Frame(page)
        top.pack(fill=tk.X, pady=(0, 8))
        ttk.Entry(top, textvariable=self.vars["asset_search"], width=42).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Combobox(top, textvariable=self.vars["asset_type"], values=("All", "Music", "Audio", "Video", "Image", "Motion", "Scenario", "Character"), state="readonly", width=13).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(top, text="Refresh index", command=self.start_asset_scan).pack(side=tk.LEFT)
        asset_body = ttk.Panedwindow(page, orient=tk.HORIZONTAL)
        asset_body.pack(fill=tk.BOTH, expand=True)
        asset_list_frame = ttk.Frame(asset_body)
        preview_frame = ttk.LabelFrame(asset_body, text="Preview", padding=14)
        asset_body.add(asset_list_frame, weight=4)
        asset_body.add(preview_frame, weight=2)
        self.asset_tree = ttk.Treeview(asset_list_frame, columns=("type", "id", "location", "details"), show="headings", selectmode="browse")
        for column, title, width, stretch in (("type", "Type", 90, False), ("id", "Asset id", 220, False), ("location", "Location", 620, True), ("details", "Details", 250, False)):
            self.asset_tree.heading(column, text=title)
            self.asset_tree.column(column, width=width, stretch=stretch)
        asset_scroll = ttk.Scrollbar(asset_list_frame, orient=tk.VERTICAL, command=self.asset_tree.yview)
        self.asset_tree.configure(yscrollcommand=asset_scroll.set)
        self.asset_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        asset_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.asset_tree.bind("<Double-1>", lambda _: self.open_asset())
        self.asset_tree.bind("<<TreeviewSelect>>", lambda _: self.preview_asset())
        self.asset_preview_title = tk.StringVar(value="Select an asset")
        self.asset_preview_meta = tk.StringVar(value="Extracted images appear here. Playable media opens through the installed Windows player.")
        ttk.Label(preview_frame, textvariable=self.asset_preview_title, style="Heading.TLabel", wraplength=320).pack(anchor=tk.W, pady=(0, 8))
        self.asset_preview_image = ttk.Label(preview_frame, text="No preview", anchor=tk.CENTER)
        self.asset_preview_image.pack(fill=tk.BOTH, expand=True, pady=(0, 10))
        ttk.Label(preview_frame, textvariable=self.asset_preview_meta, style="Muted.TLabel", wraplength=320, justify=tk.LEFT).pack(anchor=tk.W, fill=tk.X, pady=(0, 10))
        preview_buttons = ttk.Frame(preview_frame)
        preview_buttons.pack(fill=tk.X)
        ttk.Button(preview_buttons, text="Play / view", command=self.open_asset).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(preview_buttons, text="Reveal", command=self.reveal_asset).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(preview_buttons, text="Copy id", command=self.copy_asset_id).pack(side=tk.LEFT)
        assign_buttons = ttk.Frame(preview_frame)
        assign_buttons.pack(fill=tk.X, pady=(6, 0))
        ttk.Button(
            assign_buttons,
            text="Use as scene music",
            command=self.use_selected_asset_as_music,
        ).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(
            assign_buttons,
            text="Use as background",
            command=self.use_selected_asset_as_background,
        ).pack(side=tk.LEFT)
        bottom = ttk.Frame(page)
        bottom.pack(fill=tk.X, pady=(8, 0))
        self.asset_status = tk.StringVar(value="Waiting to index…")
        ttk.Label(bottom, textvariable=self.asset_status, style="Muted.TLabel").pack(side=tk.LEFT)

    def _build_build_tab(self) -> None:
        page = self._tab("Build & diagnostics")
        toolbar = ttk.Frame(page)
        toolbar.pack(fill=tk.X, pady=(0, 8))
        self.build_button = ttk.Button(toolbar, text="Build project", command=self.build_project)
        self.build_button.pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(toolbar, text="Validate", command=self.show_validation).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(toolbar, text="Open build output", command=lambda: self.open_external(WORKSPACE_ROOT / "editor-build")).pack(side=tk.LEFT)
        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=10)
        ttk.Button(toolbar, text="Launch once with patch", command=lambda: self.run_patch_script("Launch.ps1", "One-time fan launch")).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(toolbar, text="Install permanently", command=lambda: self.run_patch_script("Install.ps1", "Permanent install")).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(toolbar, text="Uninstall patch", command=lambda: self.run_patch_script("Uninstall.ps1", "Uninstall")).pack(side=tk.LEFT)
        self.build_log = tk.Text(page, wrap=tk.NONE, bg="#ffffff", fg=self.TEXT, insertbackground=self.TEXT, relief=tk.SOLID, borderwidth=1, highlightthickness=0, font=("Cascadia Mono", 9), padx=8, pady=8)
        self.build_log.pack(fill=tk.BOTH, expand=True)

    def _wire_traces(self) -> None:
        for name in ("project_title", "project_version", "project_continuity", "launch_scene"):
            self.vars[name].trace_add("write", lambda *_: self.commit_project())
        for name in ("scene_id", "scene_title", "template_storage", "template_target", "template_mode", "background", "music", "next_storage", "next_target"):
            self.vars[name].trace_add("write", lambda *_: self.commit_scene())
        for variable in self.bools.values():
            variable.trace_add("write", lambda *_: self.commit_scene())
        self.vars["template_storage"].trace_add("write", lambda *_: self.update_labels("template"))
        self.vars["next_storage"].trace_add("write", lambda *_: self.update_labels("next"))
        for name in ("injection_kind", "injection_id", "source_storage", "source_target", "expected_storage", "expected_target", "destination_scene", "line_speaker", "resume_target"):
            self.vars[name].trace_add("write", lambda *_: self.commit_injection())
        self.vars["asset_search"].trace_add("write", lambda *_: self.filter_assets())
        self.vars["asset_type"].trace_add("write", lambda *_: self.filter_assets())
        self.vars["native_search"].trace_add("write", lambda *_: self.filter_native_scenes())

    def _wire_shortcuts(self) -> None:
        self.bind_all("<Control-s>", lambda _: self._shortcut(self.save_file))
        self.bind_all("<Control-Shift-S>", lambda _: self._shortcut(lambda: self.save_file(True)))
        self.bind_all("<Control-o>", lambda _: self._shortcut(self.open_file))
        self.bind_all("<Control-n>", lambda _: self._shortcut(self.new_file))
        self.bind_all("<Control-f>", lambda _: self._shortcut(self.open_dialogue_search))

    @staticmethod
    def _shortcut(action) -> str:
        action()
        return "break"

    def open_external(self, path: Path) -> None:
        if not path.exists():
            messagebox.showwarning("Missing file", f"Not found:\n{path}", parent=self)
            return
        try:
            os.startfile(path)  # type: ignore[attr-defined]
        except OSError as exc:
            messagebox.showerror("Could not open asset", f"Windows does not have a player associated with this format.\n\n{exc}", parent=self)

    def commit_all(self) -> None:
        self.commit_page()
        self.commit_scene()
        self.commit_injection()
        self.commit_project()

    def new_file(self) -> None:
        if self.confirm_discard():
            self.set_project(new_project(), None)

    def open_file(self) -> None:
        if not self.confirm_discard():
            return
        path = filedialog.askopenfilename(parent=self, initialdir=PROJECT_ROOT, filetypes=(("A;C scene projects", "*.json"), ("All files", "*.*")))
        if path:
            self.open_path(Path(path))

    def open_path(self, path: Path) -> None:
        try:
            with path.open("r", encoding="utf-8-sig") as stream:
                self.set_project(json.load(stream), path.resolve())
            self.remember_project(path)
        except (OSError, json.JSONDecodeError) as exc:
            messagebox.showerror("Could not open project", str(exc), parent=self)

    def save_file(self, save_as: bool = False) -> bool:
        self.commit_all()
        errors = validate_project(self.project)
        if errors:
            messagebox.showwarning("Project needs attention", "Fix these items before saving:\n\n• " + "\n• ".join(errors[:14]), parent=self)
            return False
        path = self.project_path
        if save_as or path is None:
            selected = filedialog.asksaveasfilename(parent=self, initialdir=PROJECT_ROOT, initialfile=path.name if path else "my-project.json", defaultextension=".json", filetypes=(("A;C scene projects", "*.json"),))
            if not selected:
                return False
            path = Path(selected)
        try:
            if path.exists():
                shutil.copy2(path, Path(str(path) + ".bak"))
            temporary = Path(str(path) + ".tmp")
            temporary.write_text(json.dumps(self.project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            os.replace(temporary, path)
            self.project_path = path
            self.remember_project(path)
            self.dirty = False
            self.update_title()
            self.status_var.set(f"Saved {path.name} (previous version kept as .bak)")
            return True
        except OSError as exc:
            messagebox.showerror("Could not save project", str(exc), parent=self)
            return False

    def show_validation(self) -> None:
        self.commit_all()
        errors = validate_project(self.project)
        if errors:
            messagebox.showwarning("Validation issues", "• " + "\n• ".join(errors), parent=self)
        else:
            pages = sum(len(scene.get("pages", [])) for scene in self.project["scenes"])
            messagebox.showinfo("Validation passed", f"Project is valid.\n\n{len(self.project['scenes'])} scenes, {pages} dialogue pages, {len(self.project['injections'])} story injections.", parent=self)

    def build_project(self) -> None:
        if not self.save_file():
            return
        game_path_text = self.vars["game_path"].get().strip()
        game_path = Path(game_path_text) if game_path_text else None
        if game_path and not os.environ.get("AC_SCENARIO_JSON_ROOT", "").strip():
            archive_ready = (game_path / "windata" / "c0patch_info.psb.m").is_file() and (game_path / "windata" / "c0patch_body.bin").is_file()
            if archive_ready and not self.prepare_game_data_for_game(game_path):
                return
        configured_extract = os.environ.get("AC_EXTRACT_ROOT", "").strip()
        configured_scenario = os.environ.get("AC_SCENARIO_JSON_ROOT", "").strip()
        extract_root = Path(configured_extract).expanduser() if configured_extract else (self.catalog.extract_root or WORKSPACE_ROOT / "coz-extract")
        scenario_root = Path(configured_scenario).expanduser() if configured_scenario else self.catalog.scenario_root
        if not extract_root.is_dir():
            selected = filedialog.askdirectory(parent=self, initialdir=str(WORKSPACE_ROOT), title="Choose your decompiled CoZ archive root")
            if not selected:
                return
            extract_root = Path(selected)
        if not scenario_root.is_dir():
            selected = filedialog.askdirectory(parent=self, initialdir=str(WORKSPACE_ROOT), title="Choose your decompiled scenario JSON root")
            if not selected:
                return
            scenario_root = Path(selected)
        tool_root = Path(os.environ.get("AC_TOOL_ROOT", "").strip()).expanduser()
        if not tool_root.is_dir():
            selected = filedialog.askdirectory(
                parent=self,
                initialdir=str(WORKSPACE_ROOT),
                title="Choose external build tools (folder containing FreeMote)",
            )
            if not selected:
                return
            tool_root = Path(selected)
        if tool_root.name.lower() == "freemote":
            tool_root = tool_root.parent
        if not all((tool_root / "FreeMote" / name).is_file() for name in ("PsBuild.exe", "PsbDecompile.exe")):
            messagebox.showwarning(
                "Build tools not found",
                "Choose a tool folder containing FreeMote\\PsBuild.exe and FreeMote\\PsbDecompile.exe.\n\n"
                "The required archive tools are not bundled with this editor; set AC_TOOL_ROOT to your local copy.",
                parent=self,
            )
            return
        self.catalog.scenario_root = scenario_root
        self.tabs.select(self.tabs.tabs()[-1])
        self.build_log.delete("1.0", tk.END)
        self.build_log.insert(tk.END, "Building archive indexes…\n")
        self.build_button.configure(state="disabled")
        shell = self.find_powershell7()
        if shell is None:
            self.build_button.configure(state="normal")
            messagebox.showerror("PowerShell 7 required", "The archive compiler requires PowerShell 7, but pwsh.exe was not found. Install PowerShell 7 and restart the editor.", parent=self)
            return
        command = [
            shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(SOURCE_ROOT / "build.ps1"),
            "-ExtractRoot", str(extract_root), "-ToolRoot", str(tool_root),
            "-BaseScenarioJsonRoot", str(scenario_root), "-OutputRoot", str(WORKSPACE_ROOT / "editor-build"),
            "-ProjectPath", str(self.project_path),
        ]
        threading.Thread(target=self._build_worker, args=(command,), daemon=True).start()
        self.after(100, self.poll_worker)

    def _build_worker(self, command: list[str]) -> None:
        try:
            process = subprocess.Popen(command, cwd=SOURCE_ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
            assert process.stdout
            for line in process.stdout:
                self.worker_messages.put(("build", line))
            code = process.wait()
            self.worker_messages.put(("build", "\nBuild finished successfully. Output: editor-build\n" if code == 0 else f"\nBuild failed with exit code {code}.\n"))
            self.worker_messages.put(("build_done", "Build succeeded" if code == 0 else "Build failed — see diagnostics"))
        except OSError as exc:
            self.worker_messages.put(("build", f"\nCould not start build: {exc}\n"))
            self.worker_messages.put(("build_done", "Build could not start"))

    def run_patch_script(self, script_name: str, label: str) -> None:
        game_path_text = self.vars["game_path"].get().strip()
        game_path = Path(game_path_text) if game_path_text else None
        if game_path is None or not game_path.is_dir():
            messagebox.showwarning("Game install not found", f"Choose the ANONYMOUS;CODE install directory first.\n\n{game_path_text or '(not selected)'}", parent=self)
            return
        if script_name in {"Install.ps1", "Uninstall.ps1"}:
            action = "install the patch permanently" if script_name == "Install.ps1" else "uninstall the patch and restore the verified CoZ backup"
            if not messagebox.askyesno(label, f"Are you sure you want to {action}?\n\nClose the game and launcher before continuing.", parent=self):
                return
        shell = self.find_powershell7() or shutil.which("powershell") or "powershell.exe"
        command = [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(BUNDLE_ROOT / script_name), "-GamePath", str(game_path)]
        self.tabs.select(self.tabs.tabs()[-1])
        self.build_log.delete("1.0", tk.END)
        self.build_log.insert(tk.END, f"{label}: {game_path}\n\n")
        threading.Thread(target=self._build_worker, args=(command,), daemon=True).start()
        self.after(100, self.poll_worker)

    @staticmethod
    def find_powershell7() -> str | None:
        direct = shutil.which("pwsh")
        if direct:
            return direct
        installed = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "PowerShell" / "7" / "pwsh.exe"
        if installed.is_file():
            return str(installed)
        return None

    def confirm_discard(self) -> bool:
        if not self.dirty:
            return True
        answer = messagebox.askyesnocancel("Unsaved changes", "Save changes to the current project?", parent=self)
        return answer is False or (answer is True and self.save_file())

    def on_close(self) -> None:
        if self.confirm_discard():
            self.save_preferences()
            self.destroy()

    def mark_dirty(self) -> None:
        if self.loading:
            return
        self.dirty = True
        self.update_title()

    def update_title(self) -> None:
        name = self.project_path.name if self.project_path else "Untitled"
        self.title(f"{'*' if self.dirty else ''}A;C Script Studio — {name}")

    @staticmethod
    def _set_optional(container: dict, key: str, value: str) -> None:
        value = value.strip()
        if value:
            container[key] = value
        else:
            container.pop(key, None)

    @staticmethod
    def _star(value: str) -> str:
        value = value.strip()
        return value if value.startswith("*") else "*" + (value or "start")


def main() -> int:
    parser = argparse.ArgumentParser(description="Edit ANONYMOUS;CODE custom scene projects.")
    parser.add_argument("project", nargs="?", help="Project JSON to open")
    parser.add_argument("--validate", dest="validate_path", help="Validate a project without opening the GUI")
    args = parser.parse_args()
    if args.validate_path:
        try:
            with Path(args.validate_path).open("r", encoding="utf-8-sig") as stream:
                project = ensure_project(json.load(stream))
            errors = validate_project(project)
            if errors:
                print("\n".join(errors), file=sys.stderr)
                return 2
            print(f"Valid project: {len(project['scenes'])} scene(s), {len(project['injections'])} injection(s).")
            return 0
        except (OSError, json.JSONDecodeError) as exc:
            print(exc, file=sys.stderr)
            return 1
    ACEditor(args.project).mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
