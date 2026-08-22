import os
import sys
from pathlib import Path
import tkinter as tk
from tkinter import ttk


if getattr(sys, "frozen", False):
    WORKSPACE_ROOT = Path(sys.executable).resolve().parent
    SOURCE_ROOT = Path(sys._MEIPASS).resolve() / "SOURCE"
else:
    SOURCE_ROOT = Path(__file__).resolve().parent.parent
    WORKSPACE_ROOT = SOURCE_ROOT.parent
DEVELOPER_GUIDE = WORKSPACE_ROOT / "Developer-Guide.md"
if not DEVELOPER_GUIDE.is_file():
    DEVELOPER_GUIDE = SOURCE_ROOT / "DEVELOPER-GUIDE.md"


class EditorViewMixin:
    def _configure_style(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure(
            ".", background=self.BG, foreground=self.TEXT,
            fieldbackground=self.INPUT, font=("Segoe UI", 10)
        )
        style.configure("TFrame", background=self.BG)
        style.configure("Panel.TFrame", background=self.PANEL)
        style.configure("TLabel", background=self.BG, foreground=self.TEXT)
        style.configure("Muted.TLabel", foreground=self.MUTED)
        style.configure("Heading.TLabel", foreground=self.ACCENT, font=("Segoe UI Semibold", 11))
        style.configure("TButton", padding=(10, 6), background="#ffffff", foreground=self.TEXT, bordercolor=self.BORDER)
        style.map("TButton", background=[("active", "#eaf3fb")], foreground=[("active", self.ACCENT)])
        style.configure("TEntry", padding=6, fieldbackground="#ffffff", foreground=self.TEXT)
        style.configure("TCombobox", padding=5, fieldbackground="#ffffff", foreground=self.TEXT)
        style.configure("Treeview", background="#ffffff", fieldbackground="#ffffff", foreground=self.TEXT, rowheight=29)
        style.map("Treeview", background=[("selected", self.SELECT)], foreground=[("selected", self.TEXT)])
        style.configure("Treeview.Heading", background="#edf2f7", foreground=self.TEXT, font=("Segoe UI Semibold", 9))
        style.configure("TNotebook", background=self.BG, borderwidth=0)
        style.configure("TNotebook.Tab", padding=(14, 8), background="#e9eef5", foreground=self.TEXT)
        style.map("TNotebook.Tab", background=[("selected", "#ffffff")], foreground=[("selected", self.ACCENT)])
        style.configure("TLabelframe", background=self.BG, foreground=self.TEXT)
        style.configure("TLabelframe.Label", background=self.BG, foreground=self.ACCENT)

    def _create_variables(self) -> None:
        names = (
            "project_title", "project_version", "project_continuity", "launch_scene",
            "game_path", "scene_id", "scene_title", "template_storage", "template_target",
            "template_mode", "background", "music", "next_storage", "next_target",
            "injection_kind", "injection_id", "source_storage", "source_target",
            "expected_storage", "expected_target", "destination_scene", "line_speaker",
            "resume_target", "asset_search", "asset_type", "native_search",
        )
        self.vars = {name: tk.StringVar() for name in names}
        self.bools = {name: tk.BooleanVar() for name in ("speaker_focus", "hide_unlisted", "next_enabled")}
        self.vars["asset_type"].set("All")
        self.vars["game_path"].set(os.environ.get("AC_GAME_PATH", ""))

    def _build_ui(self) -> None:
        self._build_menu()
        body = ttk.Panedwindow(self, orient=tk.HORIZONTAL)
        body.pack(fill=tk.BOTH, expand=True)

        left = ttk.Frame(body, style="Panel.TFrame", padding=10)
        body.add(left, weight=0)
        ttk.Label(left, text="SCENES", style="Heading.TLabel", background=self.PANEL).pack(anchor=tk.W, pady=(0, 8))
        self.scene_views = ttk.Notebook(left)
        self.scene_views.pack(fill=tk.BOTH, expand=True)
        project_view = ttk.Frame(self.scene_views, style="Panel.TFrame", padding=4)
        native_view = ttk.Frame(self.scene_views, style="Panel.TFrame", padding=4)
        self.scene_views.add(project_view, text="Project")
        self.scene_views.add(native_view, text="Game")

        self.scene_list = tk.Listbox(
            project_view, width=36, bg="#ffffff", fg=self.TEXT,
            selectbackground=self.SELECT, selectforeground=self.TEXT,
            relief=tk.FLAT, activestyle="none", font=("Segoe UI", 10),
            highlightthickness=1, highlightbackground=self.BORDER,
        )
        self.scene_list.pack(fill=tk.BOTH, expand=True)
        self.scene_list.bind("<<ListboxSelect>>", self.select_scene)
        self.scene_list.bind("<Button-3>", self.project_context_menu)
        scene_buttons = ttk.Frame(project_view, style="Panel.TFrame")
        scene_buttons.pack(fill=tk.X, pady=(8, 0))
        for text, action in (("+ Add", self.add_scene), ("Duplicate", self.duplicate_scene), ("Remove", self.remove_scene)):
            ttk.Button(scene_buttons, text=text, command=action).pack(side=tk.LEFT, padx=(0, 5))

        native_filter = ttk.Frame(native_view, style="Panel.TFrame")
        native_filter.pack(fill=tk.X, pady=(0, 6))
        ttk.Entry(native_filter, textvariable=self.vars["native_search"]).pack(
            side=tk.LEFT, fill=tk.X, expand=True
        )
        self.native_scene_status = tk.StringVar(value="Waiting for game data…")
        ttk.Label(
            native_view,
            textvariable=self.native_scene_status,
            style="Muted.TLabel",
            background=self.PANEL,
        ).pack(fill=tk.X, pady=(0, 6))
        native_tree_frame = ttk.Frame(native_view, style="Panel.TFrame")
        native_tree_frame.pack(fill=tk.BOTH, expand=True)
        self.native_scene_tree = ttk.Treeview(
            native_tree_frame, columns=("storage", "label", "title", "pages"),
            show="headings", selectmode="browse",
        )
        for column, title, width in (("storage", "Storage", 110), ("label", "Label", 150), ("title", "Title", 160), ("pages", "Pages", 48)):
            self.native_scene_tree.heading(column, text=title)
            self.native_scene_tree.column(column, width=width, stretch=column == "title")
        native_scroll = ttk.Scrollbar(native_tree_frame, orient=tk.VERTICAL, command=self.native_scene_tree.yview)
        self.native_scene_tree.configure(yscrollcommand=native_scroll.set)
        self.native_scene_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        native_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.native_scene_tree.bind("<Double-1>", lambda _: self.view_native_scene())
        self.native_scene_tree.bind("<Button-3>", self.native_context_menu)

        self.tabs = ttk.Notebook(body)
        body.add(self.tabs, weight=1)
        self._build_project_tab()
        self._build_scene_tab()
        self._build_dialogue_tab()
        self._build_branches_tab()
        self._build_assets_tab()
        self._build_build_tab()
        self.status_var = tk.StringVar(value="Ready")
        ttk.Label(self, textvariable=self.status_var, padding=(10, 6), style="Muted.TLabel").pack(fill=tk.X)

    def _build_menu(self) -> None:
        menu = tk.Menu(self, tearoff=False, bg=self.PANEL, fg=self.TEXT)
        file_menu = tk.Menu(menu, tearoff=False)
        file_menu.add_command(label="New", accelerator="Ctrl+N", command=self.new_file)
        file_menu.add_command(label="Open…", accelerator="Ctrl+O", command=self.open_file)
        self.recent_menu = tk.Menu(file_menu, tearoff=False)
        file_menu.add_cascade(label="Open recent", menu=self.recent_menu)
        file_menu.add_separator()
        file_menu.add_command(label="Save", accelerator="Ctrl+S", command=self.save_file)
        file_menu.add_command(label="Save as…", accelerator="Ctrl+Shift+S", command=lambda: self.save_file(True))
        menu.add_cascade(label="File", menu=file_menu)
        self.refresh_recent_menu()
        edit_menu = tk.Menu(menu, tearoff=False)
        edit_menu.add_command(
            label="Find dialogue…",
            accelerator="Ctrl+F",
            command=self.open_dialogue_search,
        )
        menu.add_cascade(label="Edit", menu=edit_menu)
        tools_menu = tk.Menu(menu, tearoff=False)
        tools_menu.add_command(label="Validate project", command=self.show_validation)
        tools_menu.add_command(label="Build project", command=self.build_project)
        tools_menu.add_command(label="Open developer guide", command=lambda: self.open_external(DEVELOPER_GUIDE))
        menu.add_cascade(label="Tools", menu=tools_menu)
        self.configure(menu=menu)

    def _tab(self, title: str) -> ttk.Frame:
        outer = ttk.Frame(self.tabs, padding=12)
        self.tabs.add(outer, text=title)
        return outer

    def _form(self, parent) -> ttk.Frame:
        frame = ttk.Frame(parent, padding=12)
        frame.columnconfigure(1, weight=1)
        return frame

    def _row(self, form, row: int, label: str, widget, help_text: str | None = None) -> int:
        ttk.Label(form, text=label, style="Muted.TLabel").grid(row=row, column=0, sticky="nw", padx=(0, 18), pady=8)
        widget.grid(row=row, column=1, sticky="ew", pady=5)
        if help_text:
            ttk.Label(form, text=help_text, style="Muted.TLabel", wraplength=760).grid(row=row + 1, column=1, sticky="w", pady=(0, 7))
            return row + 2
        return row + 1

    def _build_project_tab(self) -> None:
        page = self._tab("Project")
        form = self._form(page)
        form.pack(fill=tk.X)
        row = 0
        row = self._row(form, row, "Project title", ttk.Entry(form, textvariable=self.vars["project_title"]))
        row = self._row(form, row, "Version", ttk.Entry(form, textvariable=self.vars["project_version"]))
        row = self._row(form, row, "Continuity note", ttk.Entry(form, textvariable=self.vars["project_continuity"]))
        self.launch_combo = ttk.Combobox(form, textvariable=self.vars["launch_scene"], state="readonly")
        row = self._row(form, row, "GAME START scene", self.launch_combo, "The fan launcher opens this custom scene for fast testing.")

        game_path_row = ttk.Frame(form)
        ttk.Entry(game_path_row, textvariable=self.vars["game_path"]).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(game_path_row, text="Browse…", command=self.choose_game_path).pack(side=tk.LEFT, padx=(6, 0))
        row = self._row(form, row, "Game install", game_path_row, "Choose your local ANONYMOUS;CODE install. It is not bundled with this editor.")

        self.voice_text = tk.Text(
            form, height=8, bg=self.INPUT, fg=self.TEXT, insertbackground=self.TEXT,
            relief=tk.SOLID, borderwidth=1, highlightthickness=0, padx=7, pady=7,
        )
        self.voice_text.bind("<FocusOut>", lambda _: self.commit_project())
        self._row(form, row, "Voiced characters", self.voice_text, "One exact internal speaker key per line. Listed characters receive matching native voice cues.")

    def _build_scene_tab(self) -> None:
        page = self._tab("Scene setup")
        self.scene_setup_tab = page
        canvas = tk.Canvas(page, bg=self.BG, highlightthickness=0)
        scrollbar = ttk.Scrollbar(page, orient=tk.VERTICAL, command=canvas.yview)
        form = self._form(canvas)
        window = canvas.create_window((0, 0), window=form, anchor="nw")
        form.bind("<Configure>", lambda _: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda event: canvas.itemconfigure(window, width=event.width))
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        row = 0
        row = self._row(form, row, "Scene id", ttk.Entry(form, textvariable=self.vars["scene_id"]), "Use a unique ac_ex_ name with letters, numbers, and underscores.")
        row = self._row(form, row, "Scene title", ttk.Entry(form, textvariable=self.vars["scene_title"]))
        self.template_storage_combo = ttk.Combobox(form, textvariable=self.vars["template_storage"])
        row = self._row(form, row, "Template storage", self.template_storage_combo)
        self.template_target_combo = ttk.Combobox(form, textvariable=self.vars["template_target"])
        row = self._row(form, row, "Template label", self.template_target_combo)
        template_mode = ttk.Combobox(
            form,
            textvariable=self.vars["template_mode"],
            values=("blank", "native"),
            state="readonly",
        )
        row = self._row(
            form,
            row,
            "Template mode",
            template_mode,
            "Blank supports any page count. Native retains template choreography and requires the same page count.",
        )
        row = self._row(form, row, "Background asset", ttk.Entry(form, textvariable=self.vars["background"]))
        self.music_combo = ttk.Combobox(form, textvariable=self.vars["music"])
        row = self._row(form, row, "Music", self.music_combo, "Choose a native bgm id, or leave blank to retain the template music.")

        checks = ttk.Frame(form)
        ttk.Checkbutton(checks, text="Speaker focus (custom staging)", variable=self.bools["speaker_focus"]).pack(anchor=tk.W)
        ttk.Checkbutton(checks, text="Hide unlisted native characters", variable=self.bools["hide_unlisted"]).pack(anchor=tk.W)
        row = self._row(form, row, "Presentation", checks)

        character_panel = ttk.Frame(form)
        self.character_list = tk.Listbox(
            character_panel, height=5, bg="#ffffff", fg=self.TEXT,
            selectbackground=self.SELECT, selectforeground=self.TEXT,
            relief=tk.SOLID, borderwidth=1, highlightthickness=0,
        )
        self.character_list.pack(side=tk.LEFT, fill=tk.X, expand=True)
        character_controls = ttk.Frame(character_panel)
        character_controls.pack(side=tk.LEFT, fill=tk.Y, padx=(8, 0))
        self.character_pick_combo = ttk.Combobox(character_controls, state="readonly", width=25)
        self.character_pick_combo.pack(fill=tk.X, pady=(0, 5))
        ttk.Button(character_controls, text="Add character", command=self.add_scene_character).pack(fill=tk.X, pady=(0, 5))
        ttk.Button(character_controls, text="Remove selected", command=self.remove_scene_character).pack(fill=tk.X)
        row = self._row(
            form,
            row,
            "Scene characters",
            character_panel,
            "Names are shown as internal key (English translation). The exact key is saved to project.json and used by the game.",
        )

        next_branch = ttk.Checkbutton(
            form,
            text="Continue to another scene or native label",
            variable=self.bools["next_enabled"],
        )
        row = self._row(form, row, "Next branch", next_branch)
        self.next_storage_combo = ttk.Combobox(form, textvariable=self.vars["next_storage"])
        row = self._row(form, row, "Next storage", self.next_storage_combo)
        self.next_target_combo = ttk.Combobox(form, textvariable=self.vars["next_target"])
        row = self._row(form, row, "Next label", self.next_target_combo)
        quick = ttk.Frame(form)
        self.quick_branch_combo = ttk.Combobox(quick, state="readonly", width=38)
        self.quick_branch_combo.pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(quick, text="Point to selected custom scene", command=self.point_to_scene).pack(side=tk.LEFT, padx=6)
        row = self._row(form, row, "Quick custom branch", quick)
        ttk.Button(form, text="Use this scene for GAME START testing", command=self.set_start_scene).grid(row=row, column=1, sticky="w", pady=12)

    def _build_dialogue_tab(self) -> None:
        page = self._tab("Dialogue")
        self.dialogue_tab = page
        toolbar = ttk.Frame(page)
        toolbar.pack(fill=tk.X, pady=(0, 8))
        for text, action in (
            ("+ Page", self.add_page), ("Duplicate", self.duplicate_page),
            ("Delete", self.remove_page), ("Move up", lambda: self.move_page(-1)),
            ("Move down", lambda: self.move_page(1)),
        ):
            ttk.Button(toolbar, text=text, command=action).pack(side=tk.LEFT, padx=(0, 5))

        split = ttk.Panedwindow(page, orient=tk.VERTICAL)
        split.pack(fill=tk.BOTH, expand=True)
        list_frame = ttk.Frame(split)
        edit_frame = self._form(split)
        split.add(list_frame, weight=3)
        split.add(edit_frame, weight=2)
        self.page_tree = ttk.Treeview(
            list_frame, columns=("number", "speaker", "text", "voice", "window"),
            show="headings", selectmode="browse",
        )
        for column, title, width, stretch in (
            ("number", "#", 45, False), ("speaker", "Speaker", 130, False),
            ("text", "Dialogue text", 580, True), ("voice", "Voice id", 180, False),
            ("window", "Window", 100, False),
        ):
            self.page_tree.heading(column, text=title)
            self.page_tree.column(column, width=width, stretch=stretch)
        self.page_tree.pack(fill=tk.BOTH, expand=True)
        self.page_tree.bind("<<TreeviewSelect>>", self.select_page)

        self.page_speaker = tk.StringVar()
        self.page_voice = tk.StringVar()
        self.page_window = tk.StringVar()
        row = 0
        self.page_speaker_combo = ttk.Combobox(edit_frame, textvariable=self.page_speaker)
        row = self._row(
            edit_frame,
            row,
            "Speaker",
            self.page_speaker_combo,
            "Names are shown as internal key (English translation). The exact key is saved; type a custom key if it is not in the catalog. Leave blank for narration.",
        )
        row = self._row(edit_frame, row, "Voice id", ttk.Entry(edit_frame, textvariable=self.page_voice))
        row = self._row(edit_frame, row, "Window", ttk.Combobox(edit_frame, textvariable=self.page_window, values=("", "dialogue", "narration"), state="readonly"))
        self.page_text = tk.Text(
            edit_frame, height=7, wrap=tk.WORD, bg=self.INPUT, fg=self.TEXT,
            insertbackground=self.TEXT, relief=tk.SOLID, borderwidth=1,
            highlightthickness=0, padx=8, pady=8,
        )
        self.page_text.bind("<FocusOut>", lambda _: self.commit_page())
        self._row(edit_frame, row, "Dialogue text", self.page_text)
        for variable in (self.page_speaker, self.page_voice, self.page_window):
            variable.trace_add("write", lambda *_: self.commit_page())
