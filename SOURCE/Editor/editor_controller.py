from __future__ import annotations

import copy
import re
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

if __package__:
    from .project_model import ensure_project
else:
    from project_model import ensure_project


class EditorControllerMixin:
    @property
    def current_scene(self) -> dict | None:
        if self.scene_index is None or not (0 <= self.scene_index < len(self.project["scenes"])):
            return None
        return self.project["scenes"][self.scene_index]

    @property
    def current_injection(self) -> dict | None:
        if self.injection_index is None or not (0 <= self.injection_index < len(self.project["injections"])):
            return None
        return self.project["injections"][self.injection_index]

    def set_project(self, project: dict, path: Path | None) -> None:
        self.loading = True
        self.project = ensure_project(project)
        self.project_path = path
        self.scene_index = None
        self.page_index = None
        self.injection_index = None
        metadata = self.project["metadata"]
        self.vars["project_title"].set(metadata.get("title", ""))
        self.vars["project_version"].set(metadata.get("version", ""))
        self.vars["project_continuity"].set(metadata.get("continuity", ""))
        self.voice_text.delete("1.0", tk.END)
        self.voice_text.insert("1.0", "\n".join(self.project["voiceCharacters"]))
        self.reload_scene_choices()
        self.reload_injections()
        self.loading = False
        self.dirty = False
        self.update_title()
        if self.project["scenes"]:
            self.scene_list.selection_set(0)
            self.scene_list.event_generate("<<ListboxSelect>>")
        self.status_var.set(f"Opened {path.name}" if path else "New project")

    def reload_scene_choices(self) -> None:
        current = self.scene_index
        self.scene_list.delete(0, tk.END)
        labels = []
        ids = []
        for scene in self.project["scenes"]:
            labels.append(f"{scene.get('title', '')}  ({scene.get('id', '')})")
            ids.append(scene.get("id", ""))
            self.scene_list.insert(tk.END, labels[-1])
        self.launch_combo.configure(values=ids)
        self.quick_branch_combo.configure(values=labels)
        self.destination_combo.configure(values=ids)
        self.vars["launch_scene"].set(self.project["launchAlias"].get("sourceScene", ""))
        if current is not None and current < len(labels):
            self.scene_list.selection_set(current)

    def select_scene(self, _event=None) -> None:
        selected = self.scene_list.curselection()
        if not selected:
            return
        self.commit_page()
        self.commit_scene()
        self.scene_index = selected[0]
        scene = self.current_scene
        if scene is None:
            return
        self.loading = True
        template = scene["template"]
        presentation = scene.get("presentation") or {}
        next_edge = scene.get("next")
        values = {
            "scene_id": scene.get("id", ""), "scene_title": scene.get("title", ""),
            "template_storage": template.get("storage", ""), "template_target": template.get("target", "*start"),
            "template_mode": template.get("mode", "native"), "background": presentation.get("background", ""),
            "music": presentation.get("music", ""), "next_storage": (next_edge or {}).get("storage", ""),
            "next_target": (next_edge or {}).get("target", "*start"),
        }
        for name, value in values.items():
            self.vars[name].set(value)
        self.bools["speaker_focus"].set(bool(presentation.get("speakerFocus", False)))
        self.bools["hide_unlisted"].set(bool(presentation.get("hideUnlisted", False)))
        self.bools["next_enabled"].set(next_edge is not None)
        self.loading = False
        self.update_next_state()
        self.update_labels("template")
        self.update_labels("next")
        self.reload_scene_characters()
        self.reload_pages()

    def commit_project(self) -> None:
        if self.loading:
            return
        metadata = self.project["metadata"]
        metadata["title"] = self.vars["project_title"].get()
        metadata["version"] = self.vars["project_version"].get()
        continuity = self.vars["project_continuity"].get().strip()
        if continuity:
            metadata["continuity"] = continuity
        else:
            metadata.pop("continuity", None)
        voices = [line.strip() for line in self.voice_text.get("1.0", tk.END).splitlines() if line.strip()]
        self.project["voiceCharacters"] = list(dict.fromkeys(voices))
        if self.vars["launch_scene"].get():
            self.project["launchAlias"]["sourceScene"] = self.vars["launch_scene"].get()
        self.mark_dirty()

    def commit_scene(self) -> None:
        if self.loading or self.current_scene is None:
            return
        scene = self.current_scene
        old_id = scene.get("id", "")
        scene["id"] = self.vars["scene_id"].get().strip()
        scene["title"] = self.vars["scene_title"].get()
        template = scene.setdefault("template", {})
        template.update(storage=self.vars["template_storage"].get().strip(), target=self._star(self.vars["template_target"].get()), mode=self.vars["template_mode"].get() or "native")
        presentation = scene.setdefault("presentation", {})
        self._set_optional(presentation, "background", self.vars["background"].get())
        self._set_optional(presentation, "music", self.vars["music"].get())
        presentation["speakerFocus"] = self.bools["speaker_focus"].get()
        presentation["hideUnlisted"] = self.bools["hide_unlisted"].get()
        if self.bools["next_enabled"].get():
            scene["next"] = {"storage": self.vars["next_storage"].get().strip(), "target": self._star(self.vars["next_target"].get())}
        else:
            scene["next"] = None
        if self.project["launchAlias"].get("sourceScene") == old_id:
            self.project["launchAlias"]["sourceScene"] = scene["id"]
        self.update_next_state()
        self.mark_dirty()

    def update_next_state(self) -> None:
        state = "normal" if self.bools["next_enabled"].get() else "disabled"
        self.next_storage_combo.configure(state=state)
        self.next_target_combo.configure(state=state)
        self.quick_branch_combo.configure(state="readonly" if state == "normal" else "disabled")

    def update_labels(self, which: str) -> None:
        if self.loading:
            return
        if which == "template":
            combo, storage = self.template_target_combo, self.vars["template_storage"].get()
        else:
            combo, storage = self.next_target_combo, self.vars["next_storage"].get()
        combo.configure(values=self.catalog.labels(storage))

    def add_scene(self) -> None:
        number = 1
        ids = {scene.get("id") for scene in self.project["scenes"]}
        while f"ac_ex_scene_{number:02}" in ids:
            number += 1
        scene = {
            "id": f"ac_ex_scene_{number:02}", "title": "NEW SCENE",
            "template": {"storage": "ac_03_20.ks", "target": "*flashback_1", "mode": "blank"},
            "presentation": {"background": "acb_0000n", "music": "bgm04", "hideUnlisted": False, "speakerFocus": False},
            "next": None, "pages": [{"speaker": "", "text": "New dialogue page."}],
        }
        self.project["scenes"].append(scene)
        new_index = len(self.project["scenes"]) - 1
        self.reload_scene_choices()
        self.scene_list.selection_clear(0, tk.END)
        self.scene_list.selection_set(new_index)
        self.scene_list.event_generate("<<ListboxSelect>>")
        self.mark_dirty()

    def duplicate_scene(self) -> None:
        if self.current_scene is None:
            return
        scene = copy.deepcopy(self.current_scene)
        base = scene.get("id", "scene") + "_copy"
        ident, number = base, 2
        ids = {item.get("id") for item in self.project["scenes"]}
        while ident in ids:
            ident = f"{base}{number}"
            number += 1
        scene["id"] = ident
        scene["title"] = scene.get("title", "") + " COPY"
        self.project["scenes"].append(scene)
        new_index = len(self.project["scenes"]) - 1
        self.reload_scene_choices()
        self.scene_list.selection_clear(0, tk.END)
        self.scene_list.selection_set(new_index)
        self.scene_list.event_generate("<<ListboxSelect>>")
        self.mark_dirty()

    def remove_scene(self) -> None:
        if self.current_scene is None or len(self.project["scenes"]) <= 1:
            return
        if not messagebox.askyesno("Remove scene", f"Remove '{self.current_scene.get('title', '')}'?", parent=self):
            return
        self.commit_scene()
        removed = self.project["scenes"].pop(self.scene_index)
        new_index = min(self.scene_index, len(self.project["scenes"]) - 1)
        self.scene_index = None
        if self.project["launchAlias"].get("sourceScene") == removed.get("id"):
            self.project["launchAlias"]["sourceScene"] = self.project["scenes"][0]["id"]
        self.reload_scene_choices()
        self.scene_list.selection_set(new_index)
        self.scene_list.event_generate("<<ListboxSelect>>")
        self.mark_dirty()

    def point_to_scene(self) -> None:
        index = self.quick_branch_combo.current()
        if not (0 <= index < len(self.project["scenes"])):
            return
        self.bools["next_enabled"].set(True)
        self.vars["next_storage"].set(self.project["scenes"][index]["id"] + ".ks")
        self.vars["next_target"].set("*start")

    def set_start_scene(self) -> None:
        if self.current_scene is None:
            return
        self.vars["launch_scene"].set(self.current_scene["id"])
        self.status_var.set(f"GAME START now opens {self.current_scene['id']}")

    def choose_game_path(self) -> None:
        selected = filedialog.askdirectory(parent=self, initialdir=self.vars["game_path"].get() or str(Path.home()))
        if selected:
            self.vars["game_path"].set(selected)
            self.save_preferences()
            self.start_asset_scan()

    def project_context_menu(self, event) -> None:
        index = self.scene_list.nearest(event.y)
        if not (0 <= index < len(self.project["scenes"])):
            return
        self.scene_list.selection_clear(0, tk.END)
        self.scene_list.selection_set(index)
        self.scene_list.event_generate("<<ListboxSelect>>")
        menu = tk.Menu(self, tearoff=False, bg="#ffffff", fg=self.TEXT)
        menu.add_command(label="Edit scene", command=lambda: self.scene_views.select(0))
        menu.add_command(label="Fork scene", command=self.duplicate_scene)
        menu.add_separator()
        menu.add_command(label="Use for GAME START", command=self.set_start_scene)
        menu.tk_popup(event.x_root, event.y_root)

    def native_context_menu(self, event) -> None:
        row = self.native_scene_tree.identify_row(event.y)
        if not row:
            return
        self.native_scene_tree.selection_set(row)
        menu = tk.Menu(self, tearoff=False, bg="#ffffff", fg=self.TEXT)
        menu.add_command(label="View original scene", command=self.view_native_scene)
        menu.add_command(label="Fork into project", command=self.fork_native_scene)
        menu.tk_popup(event.x_root, event.y_root)

    def selected_native_scene(self) -> tuple[str, str, str, int] | None:
        selected = self.native_scene_tree.selection()
        if not selected:
            return None
        values = self.native_scene_tree.item(selected[0], "values")
        if len(values) != 4:
            return None
        return str(values[0]), str(values[1]), str(values[2]), int(values[3])

    def view_native_scene(self) -> None:
        selected = self.selected_native_scene()
        if not selected:
            return
        storage, label, title, _ = selected
        native = self.catalog.native_scene(storage, label)
        if native is None:
            return
        dialog = tk.Toplevel(self)
        dialog.title(f"Native scene · {storage} {label}")
        dialog.geometry("900x650")
        dialog.configure(bg=self.BG)
        ttk.Label(dialog, text=f"{title}  ·  {storage} {label}", style="Heading.TLabel").pack(anchor=tk.W, padx=14, pady=(14, 6))
        ttk.Label(dialog, text="Read-only native data. Fork this scene to edit it as a project scene.", style="Muted.TLabel").pack(anchor=tk.W, padx=14, pady=(0, 8))
        text = tk.Text(dialog, wrap=tk.WORD, bg="#ffffff", fg=self.TEXT, relief=tk.SOLID, borderwidth=1, padx=10, pady=10)
        text.pack(fill=tk.BOTH, expand=True, padx=14, pady=(0, 14))
        lines = [f"Storage: {storage}", f"Label: {label}", f"Pages: {len(native.get('texts', []))}", ""]
        for index, page in enumerate(native.get("texts", []), 1):
            speaker = page[0] if isinstance(page, list) and page else ""
            body = ""
            if isinstance(page, list) and len(page) > 1 and isinstance(page[1], list) and page[1] and isinstance(page[1][0], list) and len(page[1][0]) > 1:
                body = str(page[1][0][1])
            lines.append(f"[{index}] {speaker or 'Narration'}\n{body}\n")
        text.insert("1.0", "\n".join(lines))
        text.configure(state=tk.DISABLED)

    def fork_native_scene(self) -> None:
        selected = self.selected_native_scene()
        if not selected:
            return
        storage, label, title, _ = selected
        native = self.catalog.native_scene(storage, label)
        if native is None:
            messagebox.showerror("Fork failed", "The selected native scene could not be loaded.", parent=self)
            return
        base_id = "ac_ex_fork_" + re.sub(r"[^A-Za-z0-9_]", "_", f"{storage}_{label.lstrip('*')}")
        scene_id = base_id
        suffix = 2
        existing_ids = {scene.get("id") for scene in self.project["scenes"]}
        while scene_id in existing_ids:
            scene_id = f"{base_id}_{suffix}"
            suffix += 1
        pages = []
        for page in native.get("texts", []):
            speaker = str(page[0]) if isinstance(page, list) and page and page[0] is not None else ""
            body = ""
            voice_id = None
            if isinstance(page, list) and len(page) > 1 and isinstance(page[1], list) and page[1] and isinstance(page[1][0], list):
                line = page[1][0]
                if len(line) > 1:
                    body = str(line[1])
            if isinstance(page, list) and len(page) > 2 and isinstance(page[2], dict):
                voice_id = page[2].get("voice")
            entry = {"speaker": speaker, "text": body or " ", "window": "narration" if not speaker else "dialogue"}
            if voice_id:
                entry["voiceId"] = voice_id
            pages.append(entry)
        next_edge = None
        native_nexts = native.get("nexts") or []
        if native_nexts and isinstance(native_nexts[0], dict):
            next_edge = {"storage": str(native_nexts[0].get("storage", "")), "target": self._star(str(native_nexts[0].get("target", "*start")))}
        scene = {
            "id": scene_id,
            "title": str(title or label),
            "template": {"storage": storage, "target": label, "mode": "native"},
            "next": next_edge,
            "pages": pages,
            "forkSource": {"storage": storage, "target": label, "originalScene": copy.deepcopy(native)},
        }
        self.project["scenes"].append(scene)
        if next_edge:
            injection_id = "fork_replace_" + scene_id
            self.project["injections"].append({
                "kind": "edge", "id": injection_id,
                "source": {"storage": storage, "target": label},
                "expectedNext": copy.deepcopy(next_edge),
                "destination": {"storage": scene_id + ".ks", "target": "*start"},
            })
        self.reload_scene_choices()
        new_index = len(self.project["scenes"]) - 1
        self.scene_list.selection_clear(0, tk.END)
        self.scene_list.selection_set(new_index)
        self.scene_list.event_generate("<<ListboxSelect>>")
        self.scene_views.select(0)
        self.mark_dirty()
        self.status_var.set(f"Forked {storage} {label} into {scene_id}; original data is stored under forkSource.")

    def reload_scene_characters(self) -> None:
        self.character_list.delete(0, tk.END)
        scene = self.current_scene
        if scene is None:
            return
        characters = (scene.get("presentation") or {}).get("characters") or []
        for spec in characters:
            character_id = spec.get("id", "")
            self.character_list.insert(tk.END, f"{self.catalog.display_name(character_id)}  ·  {spec.get('file', '')}")

    def add_scene_character(self) -> None:
        scene = self.current_scene
        character_id = self.catalog.key_from_display(self.character_pick_combo.get())
        if scene is None or not character_id:
            return
        presentation = scene.setdefault("presentation", {})
        characters = presentation.setdefault("characters", [])
        if any(item.get("id") == character_id for item in characters):
            return
        files = next((item[1] for item in self.catalog.characters if item[0] == character_id), ())
        sprite_files = [file_name for file_name in files if file_name.lower().endswith(".psb")]
        file_name = (sprite_files or list(files))[0] if (sprite_files or files) else ""
        if not file_name:
            messagebox.showwarning("No sprite file", f"{character_id} is present in native data, but no sprite filename was discoverable for it.", parent=self)
            return
        characters.append({"id": character_id, "file": file_name, "show": True, "x": 0, "y": 0, "z": 0, "order": len(characters), "scale": 100})
        self.reload_scene_characters()
        self.mark_dirty()

    def remove_scene_character(self) -> None:
        scene = self.current_scene
        selection = self.character_list.curselection()
        if scene is None or not selection:
            return
        characters = (scene.get("presentation") or {}).get("characters") or []
        if selection[0] < len(characters):
            characters.pop(selection[0])
            self.reload_scene_characters()
            self.mark_dirty()

    def reload_pages(self) -> None:
        self.loading = True
        self.page_tree.delete(*self.page_tree.get_children())
        if self.current_scene:
            for index, page in enumerate(self.current_scene["pages"], 1):
                preview = str(page.get("text", "")).replace("\n", " ↵ ")
                speaker = page.get("speaker", "")
                self.page_tree.insert("", tk.END, iid=str(index - 1), values=(index, self.catalog.display_name(speaker) if speaker else "Narration", preview, page.get("voiceId", ""), page.get("window", "")))
        self.page_index = None
        self.page_speaker.set("")
        self.page_voice.set("")
        self.page_window.set("")
        self.page_text.delete("1.0", tk.END)
        self.loading = False
        if self.current_scene and self.current_scene["pages"]:
            self.page_tree.selection_set("0")
            self.page_tree.focus("0")
            self.page_tree.event_generate("<<TreeviewSelect>>")

    def select_page(self, _event=None) -> None:
        selected = self.page_tree.selection()
        if not selected or self.current_scene is None:
            return
        self.commit_page()
        index = int(selected[0])
        if not (0 <= index < len(self.current_scene["pages"])):
            return
        self.page_index = index
        page = self.current_scene["pages"][index]
        self.loading = True
        self.page_speaker.set(self.catalog.display_name(page.get("speaker", "")) if page.get("speaker", "") else "")
        self.page_voice.set(page.get("voiceId", ""))
        self.page_window.set(page.get("window", ""))
        self.page_text.delete("1.0", tk.END)
        self.page_text.insert("1.0", page.get("text", ""))
        self.loading = False

    def commit_page(self) -> None:
        if self.loading or self.current_scene is None or self.page_index is None:
            return
        pages = self.current_scene["pages"]
        if not (0 <= self.page_index < len(pages)):
            return
        page = pages[self.page_index]
        page["speaker"] = self.catalog.key_from_display(self.page_speaker.get())
        page["text"] = self.page_text.get("1.0", "end-1c")
        self._set_optional(page, "voiceId", self.page_voice.get())
        self._set_optional(page, "window", self.page_window.get())
        iid = str(self.page_index)
        if self.page_tree.exists(iid):
            self.page_tree.item(iid, values=(self.page_index + 1, self.catalog.display_name(page["speaker"]) if page["speaker"] else "Narration", page["text"].replace("\n", " ↵ "), page.get("voiceId", ""), page.get("window", "")))
        self.mark_dirty()

    def add_page(self) -> None:
        if self.current_scene is None:
            return
        self.commit_page()
        index = (self.page_index + 1) if self.page_index is not None else len(self.current_scene["pages"])
        self.current_scene["pages"].insert(index, {"speaker": "", "text": "New dialogue page."})
        self.reload_pages()
        self.page_tree.selection_set(str(index))
        self.page_tree.focus(str(index))
        self.page_tree.event_generate("<<TreeviewSelect>>")
        self.mark_dirty()

    def duplicate_page(self) -> None:
        if self.current_scene is None or self.page_index is None:
            return
        self.commit_page()
        index = self.page_index + 1
        self.current_scene["pages"].insert(index, copy.deepcopy(self.current_scene["pages"][self.page_index]))
        self.reload_pages()
        self.page_tree.selection_set(str(index))
        self.page_tree.focus(str(index))
        self.page_tree.event_generate("<<TreeviewSelect>>")
        self.mark_dirty()

    def remove_page(self) -> None:
        if self.current_scene is None or self.page_index is None or len(self.current_scene["pages"]) <= 1:
            return
        index = self.page_index
        self.current_scene["pages"].pop(index)
        self.reload_pages()
        index = min(index, len(self.current_scene["pages"]) - 1)
        self.page_tree.selection_set(str(index))
        self.page_tree.event_generate("<<TreeviewSelect>>")
        self.mark_dirty()

    def move_page(self, delta: int) -> None:
        if self.current_scene is None or self.page_index is None:
            return
        self.commit_page()
        destination = self.page_index + delta
        pages = self.current_scene["pages"]
        if not (0 <= destination < len(pages)):
            return
        pages[self.page_index], pages[destination] = pages[destination], pages[self.page_index]
        self.reload_pages()
        self.page_tree.selection_set(str(destination))
        self.page_tree.focus(str(destination))
        self.page_tree.event_generate("<<TreeviewSelect>>")
        self.mark_dirty()

    def reload_injections(self) -> None:
        self.loading = True
        self.injection_list.delete(0, tk.END)
        for injection in self.project["injections"]:
            self.injection_list.insert(tk.END, f"{injection.get('id', '')}  [{injection.get('kind', '')}]")
        self.injection_index = None
        self.loading = False
        if self.project["injections"]:
            self.injection_list.selection_set(0)
            self.injection_list.event_generate("<<ListboxSelect>>")

    def select_injection(self, _event=None) -> None:
        selected = self.injection_list.curselection()
        if not selected:
            return
        self.commit_injection()
        self.injection_index = selected[0]
        injection = self.current_injection
        if injection is None:
            return
        self.loading = True
        values = {
            "injection_kind": injection.get("kind", "edge"), "injection_id": injection.get("id", ""),
            "source_storage": injection.get("source", {}).get("storage", ""), "source_target": injection.get("source", {}).get("target", "*start"),
            "expected_storage": injection.get("expectedNext", {}).get("storage", ""), "expected_target": injection.get("expectedNext", {}).get("target", "*start"),
            "destination_scene": str(injection.get("destination", {}).get("storage", "")).removesuffix(".ks"),
            "line_speaker": injection.get("line", {}).get("speaker", ""), "resume_target": injection.get("resumeTarget", ""),
        }
        for name, value in values.items():
            self.vars[name].set(value)
        self.line_text.delete("1.0", tk.END)
        self.line_text.insert("1.0", injection.get("line", {}).get("text", ""))
        self.loading = False
        self.update_after_line_state()

    def commit_injection(self) -> None:
        if self.loading or self.current_injection is None:
            return
        injection = self.current_injection
        kind = self.vars["injection_kind"].get() or "edge"
        injection["kind"] = kind
        injection["id"] = self.vars["injection_id"].get().strip()
        injection["source"] = {"storage": self.vars["source_storage"].get().strip(), "target": self._star(self.vars["source_target"].get())}
        injection["expectedNext"] = {"storage": self.vars["expected_storage"].get().strip(), "target": self._star(self.vars["expected_target"].get())}
        destination = self.vars["destination_scene"].get()
        injection["destination"] = {"storage": destination + ".ks", "target": "*start"}
        if kind == "afterLine":
            injection["line"] = {"text": self.line_text.get("1.0", "end-1c")}
            speaker = self.vars["line_speaker"].get().strip()
            if speaker:
                injection["line"]["speaker"] = speaker
            injection["resumeTarget"] = self._star(self.vars["resume_target"].get())
        else:
            injection.pop("line", None)
            injection.pop("resumeTarget", None)
        self.update_after_line_state()
        self.injection_list.delete(self.injection_index)
        self.injection_list.insert(self.injection_index, f"{injection['id']}  [{kind}]")
        self.injection_list.selection_set(self.injection_index)
        self.mark_dirty()

    def update_after_line_state(self) -> None:
        enabled = self.vars["injection_kind"].get() == "afterLine"
        self.line_speaker_entry.configure(state="normal" if enabled else "disabled")
        self.line_text.configure(state="normal" if enabled else "disabled")
        self.resume_entry.configure(state="normal" if enabled else "disabled")

    def add_injection(self, kind: str) -> None:
        target = self.current_scene or self.project["scenes"][0]
        injection = {
            "kind": kind, "id": "new_edge_branch" if kind == "edge" else "new_after_line_branch",
            "source": {"storage": "ac_01_01.ks", "target": "*start"},
            "expectedNext": {"storage": "ac_01_01.ks", "target": "*start"},
            "destination": {"storage": target["id"] + ".ks", "target": "*start"},
        }
        if kind == "afterLine":
            injection.update(line={"text": "Paste the exact native line here."}, resumeTarget="*fan_resume_here")
        self.project["injections"].append(injection)
        self.reload_injections()
        index = len(self.project["injections"]) - 1
        self.injection_list.selection_clear(0, tk.END)
        self.injection_list.selection_set(index)
        self.injection_list.event_generate("<<ListboxSelect>>")
        self.mark_dirty()

    def remove_injection(self) -> None:
        if self.injection_index is None:
            return
        self.project["injections"].pop(self.injection_index)
        self.reload_injections()
        self.mark_dirty()
