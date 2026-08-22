from __future__ import annotations

import os
import queue
import re
import shutil
import struct
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox


def workspace_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[2]

if __package__:
    from .game_data import GameDataError, prepare_game_data
else:
    from game_data import GameDataError, prepare_game_data

try:
    from PIL import Image, ImageTk
except ImportError:
    Image = None
    ImageTk = None


class AssetEditorMixin:
    def prepare_game_data_for_game(self, game_root: Path) -> bool:
        info_path = game_root / "windata" / "c0patch_info.psb.m"
        body_path = game_root / "windata" / "c0patch_body.bin"
        if not info_path.is_file() or not body_path.is_file():
            return False
        tool = self._find_psb_decompiler()
        if tool is None:
            self.status_var.set("Game selected — FreeMote is needed to index native scenes")
            return False
        self.status_var.set("Preparing a local scenario index from the selected game…")
        try:
            data = prepare_game_data(game_root, tool, lambda text: self.status_var.set(text))
        except GameDataError as exc:
            messagebox.showwarning("Game data unavailable", str(exc), parent=self)
            return False
        self.catalog.scenario_root = data["scenario_root"]
        self.catalog.extract_root = data["extract_root"]
        self.status_var.set("Local scenario index ready")
        return True

    def _find_psb_decompiler(self) -> Path | None:
        direct = os.environ.get("AC_PSB_DECOMPILE", "").strip()
        if direct:
            candidate = Path(direct).expanduser()
            if candidate.is_file():
                return candidate
        configured_root = os.environ.get("AC_TOOL_ROOT", "").strip()
        roots = [Path(configured_root).expanduser()] if configured_root else []
        for root in roots:
            candidates = (
                root if root.suffix.lower() == ".exe" else root / "FreeMote" / "PsbDecompile.exe",
                root / "PsbDecompile.exe",
            )
            for candidate in candidates:
                if candidate.is_file():
                    return candidate
        selected = filedialog.askopenfilename(
            parent=self,
            title="Choose FreeMote PsbDecompile.exe",
            filetypes=(("PsbDecompile", "PsbDecompile.exe"), ("Executables", "*.exe"), ("All files", "*.*")),
        )
        return Path(selected) if selected else None

    def _asset_is_packed(self, asset: tuple[str, str, str, str]) -> bool:
        _kind, _asset_id, location, _details = asset
        if not location:
            return True
        path = Path(location)
        if path.suffix.lower() in {".psb", ".m", ".scn"} or not path.suffix:
            return True
        try:
            with path.open("rb") as stream:
                header = stream.read(16)
                return header[:4] == b"PSB\x00" or header[8:12] == b"XWMA"
        except OSError:
            return False

    def _convert_xwma(self, source: Path, output_root: Path, safe_id: str, asset_id: str) -> Path | None:
        native_audio = output_root / f"{safe_id}.wma"
        try:
            if source.resolve() != native_audio.resolve():
                shutil.copy2(source, native_audio)
        except OSError as exc:
            messagebox.showerror("Audio preparation failed", f"Could not stage {asset_id}:\n\n{exc}", parent=self)
            return None
        vlc = self._find_vlc()
        if not vlc:
            messagebox.showwarning(
                "Audio converter not found",
                f"{asset_id} is a native XWMA file, which Windows Media Player cannot play directly.\n\n"
                "Install VLC and try Play / view again to create a standard WAV copy.",
                parent=self,
            )
            return None
        wav = output_root / f"{safe_id}.wav"
        sout = f"#transcode{{acodec=s16l,channels=1,samplerate=48000}}:std{{access=file,mux=wav,dst='{wav}'}}"
        try:
            subprocess.run([str(vlc), "--intf=dummy", "--no-video", "--play-and-exit", f"--sout={sout}", str(native_audio)], capture_output=True, timeout=180)
        except (OSError, subprocess.SubprocessError):
            pass
        if wav.is_file() and wav.stat().st_size > 44:
            return wav
        messagebox.showwarning(
            "Audio conversion failed",
            f"{asset_id} was extracted, but VLC could not convert the native XWMA container to PCM WAV.\n\n"
            f"The native copy is here:\n{native_audio}",
            parent=self,
        )
        return None

    def _extract_asset(self, asset: tuple[str, str, str, str]) -> Path | None:
        kind, asset_id, location, _details = asset
        source = Path(location) if location else None
        if source is None or not source.is_file():
            messagebox.showinfo(
                "Asset is packed",
                f"{asset_id} is a native game reference, but this index entry has no local container to extract.\n\n"
                "Extract the game's archive first, then refresh the asset index.",
                parent=self,
            )
            return None
        tool = self._find_psb_decompiler()
        if tool is None:
            messagebox.showwarning(
                "Extractor not selected",
                "Packed media needs the user's own FreeMote PsbDecompile.exe.\n\n"
                "Set AC_TOOL_ROOT to a folder containing FreeMote, or choose PsbDecompile.exe when prompted.",
                parent=self,
            )
            return None
        safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", asset_id).strip("._") or "asset"
        output_root = workspace_root() / "assets" / "extracted" / safe_id
        if output_root.is_dir():
            existing = next((p for p in output_root.rglob("*") if p.is_file() and p.suffix.lower() in {".wav", ".mp3", ".ogg", ".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm"}), None)
            if existing:
                return existing
        output_root.mkdir(parents=True, exist_ok=True)
        if source.suffix.lower() == ".wma":
            return self._convert_xwma(source, output_root, safe_id, asset_id)
        self.status_var.set(f"Extracting {asset_id}…")
        try:
            completed = subprocess.run([str(tool), "-o", str(output_root), str(source)], capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.SubprocessError) as exc:
            messagebox.showerror("Extraction failed", f"Could not extract {asset_id}:\n\n{exc}", parent=self)
            return None
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout or "The extractor returned an error.").strip()
            messagebox.showerror("Extraction failed", f"Could not extract {asset_id}:\n\n{detail}", parent=self)
            return None
        candidates = [p for p in output_root.rglob("*") if p.is_file()]
        playable = next((p for p in candidates if p.suffix.lower() in {".wav", ".wma", ".mp3", ".ogg", ".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm"}), None)
        xwma = next((p for p in candidates if ".xwma" in p.name.lower()), None)
        if xwma and kind in {"Audio", "Music"}:
            playable = self._convert_xwma(xwma, output_root, safe_id, asset_id)
        if playable:
            self.status_var.set(f"Extracted {asset_id}")
            return playable
        messagebox.showinfo("Nothing playable found", f"The extractor opened {asset_id}, but did not produce a standard playable file.", parent=self)
        return None

    @staticmethod
    def _find_vlc() -> Path | None:
        configured = os.environ.get("VLC_PATH", "").strip()
        candidates = [Path(configured)] if configured else []
        candidates.extend((
            Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "VideoLAN" / "VLC" / "vlc.exe",
            Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "VideoLAN" / "VLC" / "vlc.exe",
        ))
        command = shutil.which("vlc")
        if command:
            candidates.append(Path(command))
        return next((candidate for candidate in candidates if candidate.is_file()), None)

    @staticmethod
    def _mzv_mp4_copy(path: Path, asset_id: str) -> Path:
        try:
            with path.open("rb") as stream:
                header = stream.read(256)
            if len(header) < 8 or header[4:8] != b"ftyp":
                return path
            atom_offsets = [header.find(atom, 8) for atom in (b"moov", b"mdat", b"free", b"wide")]
            atom_offsets = [offset for offset in atom_offsets if offset >= 12]
            repair_size = min(atom_offsets) - 4 if atom_offsets else 28
        except OSError:
            return path
        safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", asset_id).strip("._") or "video"
        target = workspace_root() / "assets" / "extracted" / "videos" / f"{safe_id}.mp4"
        try:
            with path.open("rb") as source:
                source_prefix = source.read(4)
            target_prefix = b""
            if target.is_file():
                with target.open("rb") as existing:
                    target_prefix = existing.read(4)
            needs_copy = not target.is_file() or target.stat().st_size != path.stat().st_size
            if source_prefix == b"\x00\x00\x00\x00" and target_prefix != struct.pack(">I", repair_size):
                needs_copy = True
            if needs_copy:
                target.parent.mkdir(parents=True, exist_ok=True)
                with path.open("rb") as source, target.open("wb") as destination:
                    prefix = source.read(4)
                    if prefix == b"\x00\x00\x00\x00":
                        destination.write(struct.pack(">I", repair_size))
                    else:
                        destination.write(prefix)
                    shutil.copyfileobj(source, destination)
            return target
        except OSError:
            return path

    def start_asset_scan(self) -> None:
        game_path = self.vars["game_path"].get().strip()
        if game_path and not os.environ.get("AC_SCENARIO_JSON_ROOT", "").strip():
            scenario_root = self.catalog.scenario_root
            if not scenario_root.is_dir() or not any(scenario_root.glob("*.scn.m.json")):
                self.prepare_game_data_for_game(Path(game_path))
        self.asset_status.set("Indexing…")
        self.status_var.set("Indexing game assets in the background…")
        threading.Thread(target=self._asset_worker, daemon=True).start()
        self.after(100, self.poll_worker)

    def _asset_worker(self) -> None:
        try:
            game_path = self.vars["game_path"].get().strip()
            self.catalog.game_root = Path(game_path) if game_path else None
            self.catalog.scan(lambda text: self.worker_messages.put(("status", text)))
            self.worker_messages.put(("assets", self.catalog.items))
        except Exception as exc:
            self.worker_messages.put(("error", f"Asset indexing failed: {exc}"))

    def poll_worker(self) -> None:
        active = False
        try:
            while True:
                kind, payload = self.worker_messages.get_nowait()
                if kind == "status":
                    self.asset_status.set(payload)
                    self.status_var.set(payload)
                    active = True
                elif kind == "assets":
                    self.assets = payload
                    self.template_storage_combo.configure(values=self.catalog.storages)
                    self.next_storage_combo.configure(values=self.catalog.storages)
                    music = sorted({item[1] for item in self.assets if item[0] == "Music"})
                    self.music_combo.configure(values=[""] + music)
                    speaker_values = [""] + [self.catalog.display_name(key) for key in self.catalog.speakers]
                    self.page_speaker_combo.configure(values=speaker_values)
                    character_values = [self.catalog.display_name(item[0]) for item in self.catalog.characters]
                    self.character_pick_combo.configure(values=character_values)
                    self.filter_native_scenes()
                    self.status_var.set(f"Indexed {len(self.catalog.native_scenes):,} native labels and {len(self.catalog.characters):,} character keys")
                    self.filter_assets()
                elif kind == "build":
                    self.build_log.insert(tk.END, payload)
                    self.build_log.see(tk.END)
                    active = True
                elif kind == "build_done":
                    self.build_button.configure(state="normal")
                    self.status_var.set(payload)
                elif kind == "error":
                    messagebox.showerror("A;C Script Studio", payload, parent=self)
        except queue.Empty:
            pass
        if active or threading.active_count() > 1:
            self.after(100, self.poll_worker)

    def filter_assets(self) -> None:
        search = self.vars["asset_search"].get().strip().lower()
        kind = self.vars["asset_type"].get() or "All"
        filtered = [item for item in self.assets if (kind == "All" or item[0] == kind) and (not search or any(search in str(value).lower() for value in item))]
        self.asset_tree.delete(*self.asset_tree.get_children())
        for index, item in enumerate(filtered):
            self.asset_tree.insert("", tk.END, iid=str(index), values=item)
        self.asset_status.set(f"{len(filtered):,} shown / {len(self.assets):,} indexed")

    def selected_asset(self) -> tuple[str, str, str, str] | None:
        selected = self.asset_tree.selection()
        if not selected:
            return None
        values = self.asset_tree.item(selected[0], "values")
        return tuple(values) if values else None

    def preview_asset(self) -> None:
        asset = self.selected_asset()
        if not asset:
            self.asset_preview_title.set("Select an asset")
            self.asset_preview_meta.set("Extracted images appear here. Playable media opens through the installed Windows player.")
            self.asset_preview_image.configure(image="", text="No preview")
            self._preview_photo = None
            return
        kind, asset_id, location, details = asset
        self.asset_preview_title.set(f"{asset_id}  ·  {kind}")
        if self._asset_is_packed(asset):
            self.asset_preview_meta.set(details + "\n\nPacked native container. Play / view will ask before extracting a playable copy.")
        else:
            self.asset_preview_meta.set(details if location else "Packed in the game archive. The id is ready to use in a scene; extract a playable copy to preview it.")
        self.asset_preview_image.configure(image="", text=kind)
        self._preview_photo = None
        if location and kind == "Image" and Image is not None and Path(location).is_file():
            try:
                image = Image.open(location)
                image.thumbnail((380, 300), Image.Resampling.LANCZOS)
                self._preview_photo = ImageTk.PhotoImage(image)
                self.asset_preview_image.configure(image=self._preview_photo, text="")
            except (OSError, ValueError):
                self.asset_preview_meta.set(details + "\n\nThis packed image format has no standard raster preview.")
        elif kind == "Video":
            self.asset_preview_image.configure(text="VIDEO\n\nUse Play / view to start it in Windows Media Player.")
        elif kind == "Audio" or kind == "Music":
            self.asset_preview_image.configure(text="AUDIO\n\nUse Play / view to listen.")
        elif kind == "Character":
            self.asset_preview_image.configure(text="CHARACTER\n\nUse Add character in Scene setup to stage this key.")

    def open_asset(self) -> None:
        asset = self.selected_asset()
        if not asset:
            return
        path = Path(asset[2]) if asset[2] else None
        if self._asset_is_packed(asset) or path is None or not path.exists():
            answer = messagebox.askyesno(
                "Extract packed asset?",
                f"{asset[1]} is stored in the game's packed format and cannot be opened directly.\n\nWould you like to extract a playable copy now?",
                parent=self,
            )
            if not answer:
                return
            path = self._extract_asset(asset)
            if path is None:
                return
        if path.suffix.lower() == ".mzv":
            path = self._mzv_mp4_copy(path, asset[1])
            vlc = self._find_vlc()
            if vlc:
                try:
                    subprocess.Popen([str(vlc), str(path)])
                    return
                except OSError:
                    pass
            players = [
                Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Windows Media Player" / "wmplayer.exe",
                Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Windows Media Player" / "wmplayer.exe",
            ]
            player = next((candidate for candidate in players if candidate.is_file()), None)
            if player:
                subprocess.Popen([str(player), str(path)])
                return
        self.open_external(path)

    def reveal_asset(self) -> None:
        asset = self.selected_asset()
        if not asset or not Path(asset[2]).exists():
            return
        subprocess.Popen(["explorer.exe", "/select,", str(Path(asset[2]))])

    def copy_asset_id(self) -> None:
        asset = self.selected_asset()
        if asset:
            self.clipboard_clear()
            self.clipboard_append(asset[1])
