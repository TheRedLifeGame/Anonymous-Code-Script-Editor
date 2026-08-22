from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk


class EditorNavigationMixin:
    def filter_native_scenes(self) -> None:
        if not hasattr(self, "native_scene_tree"):
            return
        query = self.vars["native_search"].get().strip().casefold()
        scenes = [
            scene for scene in self.catalog.native_scenes
            if not query or any(query in str(value).casefold() for value in scene)
        ]
        self.native_scene_tree.delete(*self.native_scene_tree.get_children())
        for index, scene in enumerate(scenes):
            self.native_scene_tree.insert("", tk.END, iid=str(index), values=scene)
        self.native_scene_status.set(
            f"{len(scenes):,} shown / {len(self.catalog.native_scenes):,} native labels"
        )

    def open_dialogue_search(self) -> None:
        self.commit_all()
        existing = getattr(self, "dialogue_search_window", None)
        if existing is not None and existing.winfo_exists():
            self.populate_dialogue_search(
                self.dialogue_search_tree,
                self.dialogue_search_query.get(),
            )
            existing.lift()
            existing.focus_force()
            return

        dialog = tk.Toplevel(self)
        self.dialogue_search_window = dialog
        dialog.title("Find dialogue")
        dialog.geometry("980x560")
        dialog.minsize(720, 360)
        dialog.configure(bg=self.BG)
        dialog.transient(self)

        header = ttk.Frame(dialog, padding=12)
        header.pack(fill=tk.X)
        ttk.Label(header, text="Search project dialogue", style="Heading.TLabel").pack(
            side=tk.LEFT, padx=(0, 10)
        )
        query = tk.StringVar()
        self.dialogue_search_query = query
        entry = ttk.Entry(header, textvariable=query)
        entry.pack(side=tk.LEFT, fill=tk.X, expand=True)

        columns = ("scene", "page", "speaker", "text")
        tree = ttk.Treeview(dialog, columns=columns, show="headings", selectmode="browse")
        self.dialogue_search_tree = tree
        for column, title, width, stretch in (
            ("scene", "Scene", 210, False),
            ("page", "Page", 60, False),
            ("speaker", "Speaker", 150, False),
            ("text", "Dialogue", 520, True),
        ):
            tree.heading(column, text=title)
            tree.column(column, width=width, stretch=stretch)
        scrollbar = ttk.Scrollbar(dialog, orient=tk.VERTICAL, command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(12, 0), pady=(0, 12))
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, padx=(0, 12), pady=(0, 12))

        self.dialogue_search_results = {}
        query.trace_add("write", lambda *_: self.populate_dialogue_search(tree, query.get()))
        tree.bind("<Double-1>", lambda _: self.open_dialogue_search_result(tree))
        tree.bind("<Return>", lambda _: self.open_dialogue_search_result(tree))
        self.populate_dialogue_search(tree, "")
        entry.focus_set()

    def populate_dialogue_search(self, tree: ttk.Treeview, query: str) -> None:
        needle = query.strip().casefold()
        tree.delete(*tree.get_children())
        self.dialogue_search_results = {}
        result_number = 0
        for scene_index, scene in enumerate(self.project.get("scenes", [])):
            scene_label = f"{scene.get('title', '')} ({scene.get('id', '')})"
            for page_index, page in enumerate(scene.get("pages", [])):
                speaker = str(page.get("speaker", ""))
                text = str(page.get("text", ""))
                voice = str(page.get("voiceId", ""))
                haystack = "\n".join((scene_label, speaker, text, voice)).casefold()
                if needle and needle not in haystack:
                    continue
                iid = str(result_number)
                result_number += 1
                self.dialogue_search_results[iid] = (scene_index, page_index)
                preview = " ".join(text.split())
                tree.insert(
                    "",
                    tk.END,
                    iid=iid,
                    values=(
                        scene_label,
                        page_index + 1,
                        self.catalog.display_name(speaker) if speaker else "Narration",
                        preview,
                    ),
                )

    def open_dialogue_search_result(self, tree: ttk.Treeview) -> None:
        selected = tree.selection()
        if not selected:
            return
        result = self.dialogue_search_results.get(selected[0])
        if result is None:
            return
        scene_index, page_index = result
        self.scene_list.selection_clear(0, tk.END)
        self.scene_list.selection_set(scene_index)
        self.scene_list.see(scene_index)
        self.scene_list.event_generate("<<ListboxSelect>>")
        self.tabs.select(self.dialogue_tab)
        iid = str(page_index)
        if self.page_tree.exists(iid):
            self.page_tree.selection_set(iid)
            self.page_tree.focus(iid)
            self.page_tree.see(iid)
            self.page_tree.event_generate("<<TreeviewSelect>>")

    def use_selected_asset_as_music(self) -> None:
        asset = self.selected_asset()
        if asset is None or self.current_scene is None:
            return
        if asset[0] != "Music":
            messagebox.showwarning(
                "Not a music asset",
                "Select a native music reference first.",
                parent=self,
            )
            return
        self.vars["music"].set(asset[1])
        self.tabs.select(self.scene_setup_tab)
        self.status_var.set(f"Scene music set to {asset[1]}")

    def use_selected_asset_as_background(self) -> None:
        asset = self.selected_asset()
        if asset is None or self.current_scene is None:
            return
        if asset[0] != "Image":
            messagebox.showwarning(
                "Not an image asset",
                "Select an image asset first.",
                parent=self,
            )
            return
        self.vars["background"].set(asset[1])
        self.tabs.select(self.scene_setup_tab)
        self.status_var.set(f"Scene background set to {asset[1]}")
