import os
import sys
import traceback

if sys.stdout is None:
    try: sys.stdout = open(os.devnull, "w")
    except Exception: pass
if sys.stderr is None:
    try: sys.stderr = open(os.devnull, "w")
    except Exception: pass

def uncaught_exception_handler(exc_type, exc_value, exc_traceback):
    try:
        app_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
        crash_log = os.path.join(app_dir, "crash.log")
        with open(crash_log, "a", encoding="utf-8") as f:
            f.write("".join(traceback.format_exception(exc_type, exc_value, exc_traceback)) + "\n")
    except Exception:
        pass

sys.excepthook = uncaught_exception_handler

import json
import random
import time
import threading
import hashlib
import urllib.request
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

import numpy as np
import sounddevice as sd
import miniaudio

PORT = 8765
APP_VERSION = "1.0.11"

if getattr(sys, 'frozen', False):
    APP_DIR = os.path.dirname(sys.executable)
else:
    APP_DIR = os.path.dirname(os.path.abspath(__file__))

ROOT_DIR = APP_DIR
SCRIPTS_DIR = os.path.join(APP_DIR, "scripts")
VTT_DIR = os.path.join(SCRIPTS_DIR, "VoiceTrashTalk")
SOUNDS_DIR = os.path.join(VTT_DIR, "sounds")
CONFIG_FILE = os.path.join(APP_DIR, "config.json")
LOG_FILE = os.path.join(APP_DIR, "elycde.log")

DEFAULT_CONFIG = {
    "repo": "elycde/umb",
    "branch": "main",
    "auto_update": True,
    "last_commit": ""
}

def init_environment():
    global ROOT_DIR, SCRIPTS_DIR, VTT_DIR, SOUNDS_DIR, CONFIG_FILE, LOG_FILE

    is_umbrella_root = (
        os.path.exists(os.path.join(APP_DIR, "UmbrellaLoader.exe")) or
        os.path.exists(os.path.join(APP_DIR, "LoaderKernel.dll")) or
        os.path.exists(os.path.join(APP_DIR, "configs")) or
        (os.path.exists(os.path.join(APP_DIR, "scripts")) and os.path.basename(APP_DIR).lower() != "voicetrashtalk")
    )

    if is_umbrella_root:
        ROOT_DIR = APP_DIR
        SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")
        VTT_DIR = os.path.join(SCRIPTS_DIR, "VoiceTrashTalk")
        SOUNDS_DIR = os.path.join(VTT_DIR, "sounds")
    elif os.path.basename(APP_DIR).lower() == "voicetrashtalk":
        VTT_DIR = APP_DIR
        SCRIPTS_DIR = os.path.dirname(VTT_DIR)
        ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
        SOUNDS_DIR = os.path.join(VTT_DIR, "sounds")
    elif os.path.basename(APP_DIR).lower() == "scripts":
        SCRIPTS_DIR = APP_DIR
        ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
        VTT_DIR = os.path.join(SCRIPTS_DIR, "VoiceTrashTalk")
        SOUNDS_DIR = os.path.join(VTT_DIR, "sounds")
    else:
        parent = os.path.dirname(APP_DIR)
        if os.path.basename(parent).lower() == "scripts":
            SCRIPTS_DIR = parent
            ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
            VTT_DIR = os.path.join(SCRIPTS_DIR, "VoiceTrashTalk")
            SOUNDS_DIR = os.path.join(VTT_DIR, "sounds")
        else:
            ROOT_DIR = APP_DIR
            SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")
            VTT_DIR = os.path.join(SCRIPTS_DIR, "VoiceTrashTalk")
            SOUNDS_DIR = os.path.join(VTT_DIR, "sounds")

    try:
        os.makedirs(ROOT_DIR, exist_ok=True)
        os.makedirs(SCRIPTS_DIR, exist_ok=True)
        os.makedirs(VTT_DIR, exist_ok=True)
        os.makedirs(SOUNDS_DIR, exist_ok=True)
    except Exception:
        pass

    # Clean up legacy elycde.lua in favor of MapDrawer.lua
    legacy_file = os.path.join(SCRIPTS_DIR, "elycde.lua")
    if os.path.exists(legacy_file):
        try:
            os.remove(legacy_file)
        except Exception:
            pass

    if os.path.exists(os.path.join(APP_DIR, "config.json")):
        CONFIG_FILE = os.path.join(APP_DIR, "config.json")
    elif os.path.exists(os.path.join(VTT_DIR, "config.json")):
        CONFIG_FILE = os.path.join(VTT_DIR, "config.json")
    else:
        CONFIG_FILE = os.path.join(APP_DIR, "config.json")

    LOG_FILE = os.path.join(APP_DIR, "elycde.log")

init_environment()

def log_debug(msg):
    try:
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"[{ts}] {msg}\n")
    except Exception:
        pass

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                return {**DEFAULT_CONFIG, **cfg}
        except Exception:
            pass
    save_config(DEFAULT_CONFIG)
    return DEFAULT_CONFIG

def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=4, ensure_ascii=False)
    except Exception:
        pass

def get_file_hash(filepath):
    if not os.path.exists(filepath):
        return ""
    try:
        hasher = hashlib.sha256()
        with open(filepath, "rb") as f:
            while chunk := f.read(65536):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception:
        return ""

def download_url(url, timeout=15):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "elycde-updater/2.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return resp.read()
    except Exception as e:
        log_debug(f"download_url error ({url}): {e}")
    return None

def get_remote_lua_scripts(repo, branch="main"):
    api_url = f"https://api.github.com/repos/{repo}/contents/lua?ref={branch}"
    scripts = []
    try:
        req = urllib.request.Request(api_url, headers={"User-Agent": "elycde-updater/2.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                items = json.loads(resp.read().decode("utf-8"))
                for item in items:
                    if item.get("type") == "file" and item.get("name", "").lower().endswith(".lua"):
                        scripts.append(item["name"])
    except Exception as e:
        log_debug(f"get_remote_lua_scripts error: {e}")

    default_scripts = ["MapDrawer.lua", "Settings.lua", "Visuals.lua", "VoiceTrashTalk.lua"]
    for s in default_scripts:
        if s not in scripts:
            scripts.append(s)

    return sorted(list(set(scripts)))

def check_for_updates(force=False):
    cfg = load_config()
    repo = cfg.get("repo", "elycde/umb").strip()
    branch = cfg.get("branch", "main").strip()
    if not repo:
        return False, [], "Репозиторий не указан в config.json"

    updated_files = []
    exe_updated = False

    # Check commit SHA from GitHub API (best effort)
    api_url = f"https://api.github.com/repos/{repo}/commits/{branch}"
    remote_sha = None
    try:
        req = urllib.request.Request(api_url, headers={"User-Agent": "elycde-updater/2.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                data = json.loads(resp.read().decode("utf-8"))
                remote_sha = data.get("sha", "")
    except Exception:
        pass

    last_sha = cfg.get("last_commit", "")

    # 1. Update Lua Scripts Bundle from lua/ folder
    remote_scripts = get_remote_lua_scripts(repo, branch)
    for script_name in remote_scripts:
        script_url = f"https://raw.githubusercontent.com/{repo}/{branch}/lua/{script_name}"
        script_local = os.path.join(SCRIPTS_DIR, script_name)
        content = download_url(script_url)
        if content and len(content) > 50:
            local_hash = get_file_hash(script_local)
            remote_hash = hashlib.sha256(content).hexdigest()
            if local_hash != remote_hash:
                try:
                    with open(script_local, "wb") as f:
                        f.write(content)
                    updated_files.append(script_name)
                    log_debug(f"Updated {script_name} in {SCRIPTS_DIR}")
                except Exception as e:
                    log_debug(f"Failed to write {script_name}: {e}")

    # 2. Update Default Sounds
    for snd in ["1.wav", "2.wav"]:
        snd_local = os.path.join(SOUNDS_DIR, snd)
        if not os.path.exists(snd_local):
            snd_url = f"https://raw.githubusercontent.com/{repo}/{branch}/sounds/{snd}"
            snd_content = download_url(snd_url)
            if snd_content and len(snd_content) > 1000:
                try:
                    with open(snd_local, "wb") as f:
                        f.write(snd_content)
                    updated_files.append(f"sounds/{snd}")
                    log_debug(f"Downloaded missing sound: {snd}")
                except Exception as e:
                    log_debug(f"Failed to write sound {snd}: {e}")

    # 3. Update elycde.exe (Self-update from GitHub Releases only on force and strictly newer version)
    if force and getattr(sys, 'frozen', False):
        exe_local = sys.executable
        exe_url = None
        remote_tag = ""

        try:
            rel_api = f"https://api.github.com/repos/{repo}/releases/latest"
            req = urllib.request.Request(rel_api, headers={"User-Agent": "elycde-updater/2.0"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    rel_data = json.loads(resp.read().decode("utf-8"))
                    remote_tag = rel_data.get("tag_name", "").lstrip("v")
                    for asset in rel_data.get("assets", []):
                        if asset.get("name", "").lower() == "elycde.exe":
                            exe_url = asset.get("browser_download_url")
                            break
        except Exception:
            pass

        def parse_v(v_str):
            try:
                return [int(x) for x in v_str.replace("v", "").split(".") if x.isdigit()]
            except Exception:
                return [0, 0, 0]

        is_newer = parse_v(remote_tag) > parse_v(APP_VERSION)
        if exe_url and is_newer:
            exe_content = download_url(exe_url, timeout=30)
            if exe_content and len(exe_content) > 1000000:
                local_hash = get_file_hash(exe_local)
                remote_hash = hashlib.sha256(exe_content).hexdigest()
                if local_hash != remote_hash:
                    new_exe = exe_local + ".new"
                    try:
                        with open(new_exe, "wb") as f:
                            f.write(exe_content)
                        exe_updated = True
                        log_debug(f"Downloaded new elycde.exe (v{remote_tag}) from GitHub Release. Spawning self-updater...")

                        updater_bat = os.path.join(os.path.dirname(exe_local), "updater.bat")
                        with open(updater_bat, "w", encoding="utf-8") as bf:
                            bf.write(f'''@echo off
timeout /t 1 /nobreak >nul
:loop
del "{exe_local}" >nul 2>&1
if exist "{exe_local}" (
    timeout /t 1 /nobreak >nul
    goto loop
)
move /y "{new_exe}" "{exe_local}" >nul
start "" "{exe_local}"
del "%~f0" >nul 2>&1
''')
                        subprocess.Popen(["cmd.exe", "/c", updater_bat], cwd=os.path.dirname(exe_local), creationflags=0x08000000 if os.name == 'nt' else 0)
                        time.sleep(0.5)
                        os._exit(0)
                    except Exception as e:
                        log_debug(f"Failed to apply elycde.exe update: {e}")

    if remote_sha:
        cfg["last_commit"] = remote_sha
        save_config(cfg)

    msg = ""
    if updated_files:
        msg = f"Обновлено: {', '.join(updated_files)}! Нажмите F6 в игре."
    elif exe_updated:
        msg = "Обновлен elycde.exe! Перезапуск..."
    else:
        msg = "У вас установлена последняя версия!"

    return (len(updated_files) > 0 or exe_updated), updated_files, msg

class AudioPlayer:
    def __init__(self):
        self.is_playing = False
        self._current_stop_event = None
        self._threads = []
        self._lock = threading.Lock()
        self.cable_idx = None
        self.cable_name = ""
        self.speaker_idx = None
        self.speaker_name = ""
        self.detect_devices()

    def detect_devices(self):
        try:
            devices = sd.query_devices()
            self.cable_idx = None
            self.cable_name = ""
            self.speaker_idx = sd.default.device[1]
            if self.speaker_idx is not None and self.speaker_idx >= 0:
                self.speaker_name = devices[self.speaker_idx].get("name", "Default")

            for i, d in enumerate(devices):
                name = d.get("name", "")
                if "CABLE Input" in name and d.get("max_output_channels", 0) > 0:
                    self.cable_idx = i
                    self.cable_name = name
                    break
            
            log_debug(f"Audio devices: Cable='{self.cable_name}' (idx={self.cable_idx}), Speaker='{self.speaker_name}' (idx={self.speaker_idx})")
        except Exception as e:
            log_debug(f"detect_devices error: {e}")

    def load_audio(self, filepath):
        decoded = None
        try:
            with open(filepath, "rb") as f:
                data = f.read()
            decoded = miniaudio.decode(data)
        except Exception as e1:
            try:
                decoded = miniaudio.decode_file(filepath)
            except Exception:
                try:
                    import av
                    container = av.open(filepath)
                    stream = container.streams.audio[0]
                    sr = stream.rate or 44100
                    resampler = av.AudioResampler(format='fltp', layout='stereo', rate=sr)
                    chunks = []
                    for frame in container.decode(stream):
                        res = resampler.resample(frame)
                        if res:
                            for r in res:
                                chunks.append(r.to_ndarray().T)
                    if chunks:
                        audio_data = np.vstack(chunks)
                        duration_ms = int((len(audio_data) / sr) * 1000)
                        return audio_data, sr, duration_ms
                except Exception as e_av:
                    log_debug(f"av decode error: {e_av}")
                raise e1

        sr = decoded.sample_rate
        ch = decoded.nchannels
        samples = np.array(decoded.samples, dtype=np.float32) / 32768.0
        audio_data = samples.reshape(-1, ch)

        # Auto-trim trailing dead silence so voicerecord releases naturally without hanging
        abs_samples = np.abs(audio_data)
        max_amp = np.max(abs_samples)
        if max_amp > 0.01:
            threshold = max(0.005, max_amp * 0.01)
            above = np.where(np.any(abs_samples > threshold, axis=1))[0]
            if len(above) > 0:
                last_idx = min(len(audio_data), above[-1] + int(sr * 0.12))
                if last_idx < len(audio_data) - int(sr * 0.2):
                    audio_data = audio_data[:last_idx]
                    fade_len = min(len(audio_data), int(sr * 0.05))
                    if fade_len > 0:
                        fade = np.linspace(1.0, 0.0, fade_len).reshape(-1, 1)
                        audio_data[-fade_len:] *= fade

        duration_ms = int((len(audio_data) / sr) * 1000)
        return audio_data, sr, duration_ms

    def play(self, filepath, speaker_vol=80, mic_vol=100, only_speaker=False, only_mic=False):
        self.stop()

        with self._lock:
            stop_event = threading.Event()
            self._current_stop_event = stop_event

        audio_data, sr, duration_ms = self.load_audio(filepath)

        s_vol = max(0.0, min(1.0, float(speaker_vol) / 100.0))
        m_vol = max(0.0, min(1.0, float(mic_vol) / 100.0))

        cable_audio = audio_data * m_vol
        speaker_audio = audio_data * s_vol

        use_cable = (self.cable_idx is not None) and (not only_speaker) and (m_vol > 0.001)
        use_speaker = (self.speaker_idx is not None) and (not only_mic) and (s_vol > 0.001)

        def play_stream(device, data, ev):
            try:
                channels = data.shape[1] if len(data.shape) > 1 else 1
                with sd.OutputStream(device=device, samplerate=sr, channels=channels) as stream:
                    chunk_size = 2048
                    pos = 0
                    total_len = len(data)
                    while pos < total_len and not ev.is_set():
                        chunk = data[pos : pos + chunk_size]
                        stream.write(chunk)
                        pos += chunk_size
            except Exception as e:
                log_debug(f"play_stream error (device={device}): {e}")
            finally:
                if not ev.is_set():
                    self.is_playing = False

        threads = []
        if use_cable:
            t_cable = threading.Thread(target=play_stream, args=(self.cable_idx, cable_audio, stop_event), daemon=True)
            threads.append(t_cable)
            t_cable.start()

        if use_speaker:
            t_speaker = threading.Thread(target=play_stream, args=(self.speaker_idx, speaker_audio, stop_event), daemon=True)
            threads.append(t_speaker)
            t_speaker.start()

        with self._lock:
            self._threads = threads
            self.is_playing = len(threads) > 0

        return True, duration_ms, use_cable, use_speaker

    def stop(self):
        with self._lock:
            if self._current_stop_event:
                self._current_stop_event.set()
                self._current_stop_event = None
            try:
                sd.stop()
            except Exception:
                pass
            for t in self._threads:
                if t.is_alive() and t != threading.current_thread():
                    t.join(timeout=0.1)
            self._threads = []
            self.is_playing = False

player = AudioPlayer()

def get_sound_files(subfolder=""):
    valid_exts = (".mp3", ".wav", ".wma", ".ogg", ".flac")
    target_dir = os.path.join(SOUNDS_DIR, subfolder) if subfolder else SOUNDS_DIR
    if not os.path.exists(target_dir):
        target_dir = SOUNDS_DIR
    if not os.path.exists(target_dir):
        return []

    files = []
    for root, dirs, filenames in os.walk(target_dir):
        for f in filenames:
            if f.lower().endswith(valid_exts):
                files.append(os.path.join(root, f))
    return sorted(files)

class ElycdeHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        log_debug(format % args)

    def send_json(self, data, code=200):
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))
        except Exception as e:
            log_debug(f"send_json error: {e}")

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            path = parsed.path
            query = parse_qs(parsed.query)

            if path == "/ping":
                player.detect_devices()
                files = get_sound_files()
                self.send_json({
                    "status": "running",
                    "sounds_count": len(files),
                    "cable_found": player.cable_idx is not None,
                    "cable_name": player.cable_name,
                    "speaker_name": player.speaker_name
                })
                return

            elif path == "/list":
                files = get_sound_files()
                names = [os.path.relpath(f, SOUNDS_DIR).replace("\\", "/") for f in files]
                self.send_json({
                    "status": "ok",
                    "files": names,
                    "count": len(names),
                    "cable_found": player.cable_idx is not None
                })
                return

            elif path == "/update":
                has_updates, updated_files, message = check_for_updates(force=True)
                self.send_json({
                    "status": "ok" if has_updates else "up_to_date",
                    "updated_files": updated_files,
                    "message": message
                })
                return

            elif path == "/play":
                subfolder = query.get("event", [""])[0]
                specific_file = query.get("file", [""])[0]
                
                speaker_vol = 80
                mic_vol = 100
                if "speaker_vol" in query:
                    try: speaker_vol = int(query["speaker_vol"][0])
                    except Exception: pass
                elif "volume" in query:
                    try: speaker_vol = int(query["volume"][0])
                    except Exception: pass
                
                if "mic_vol" in query:
                    try: mic_vol = int(query["mic_vol"][0])
                    except Exception: pass

                only_speaker = query.get("only_speaker", ["0"])[0] in ("1", "true")
                only_mic = query.get("only_mic", ["0"])[0] in ("1", "true")

                target_path = None
                if specific_file:
                    specific_file = unquote(specific_file).strip()
                    candidate = os.path.join(SOUNDS_DIR, specific_file.replace("/", "\\"))
                    if os.path.exists(candidate):
                        target_path = candidate
                    else:
                        base_query = os.path.basename(specific_file).lower()
                        for f in get_sound_files():
                            if os.path.basename(f).lower() == base_query:
                                target_path = f
                                break

                if not target_path:
                    files = get_sound_files(subfolder)
                    if not files and subfolder:
                        files = get_sound_files("")
                    if not files:
                        self.send_json({"status": "error", "message": "No sound files found"}, code=404)
                        return
                    target_path = random.choice(files)

                if os.path.exists(target_path):
                    ok, duration_ms, used_cable, used_speaker = player.play(
                        target_path,
                        speaker_vol=speaker_vol,
                        mic_vol=mic_vol,
                        only_speaker=only_speaker,
                        only_mic=only_mic
                    )
                    filename = os.path.basename(target_path)
                    log_debug(f"Playing '{filename}' (dur={duration_ms}ms, spk_vol={speaker_vol}%, mic_vol={mic_vol}%, cable={used_cable}, spk={used_speaker})")
                    self.send_json({
                        "status": "playing",
                        "file": filename,
                        "duration_ms": duration_ms,
                        "cable_used": used_cable,
                        "speaker_used": used_speaker,
                        "cable_found": player.cable_idx is not None
                    })
                else:
                    self.send_json({"status": "error", "message": f"File not found: {target_path}"}, code=404)
                return

            elif path == "/stop":
                player.stop()
                self.send_json({"status": "stopped"})
                return

            elif path == "/open_folder":
                try:
                    if not os.path.exists(SOUNDS_DIR):
                        os.makedirs(SOUNDS_DIR, exist_ok=True)
                    
                    opened = False
                    try:
                        os.startfile(SOUNDS_DIR)
                        opened = True
                    except Exception as e_start:
                        log_debug(f"os.startfile error: {e_start}")
                    
                    if not opened:
                        try:
                            subprocess.Popen(f'explorer.exe "{SOUNDS_DIR}"', shell=True)
                            opened = True
                        except Exception as e_sub:
                            log_debug(f"subprocess error: {e_sub}")

                    log_debug(f"Opened sounds folder: {SOUNDS_DIR}")
                    self.send_json({"status": "opened", "path": SOUNDS_DIR})
                except Exception as e:
                    log_debug(f"open_folder error: {e}")
                    self.send_json({"status": "error", "message": str(e)}, code=500)
                return

            elif path == "/open_url":
                target_url = query.get("url", [""])[0]
                if target_url:
                    target_url = unquote(target_url).strip()
                    opened = False
                    try:
                        os.startfile(target_url)
                        opened = True
                    except Exception as e_start:
                        log_debug(f"os.startfile url error: {e_start}")

                    if not opened:
                        try:
                            subprocess.Popen(f'cmd.exe /c start "" "{target_url}"', shell=True)
                            opened = True
                        except Exception as e_cmd:
                            log_debug(f"cmd start url error: {e_cmd}")

                    if not opened:
                        try:
                            import webbrowser
                            webbrowser.open(target_url)
                        except Exception as e_wb:
                            log_debug(f"webbrowser error: {e_wb}")

                    self.send_json({"status": "opened", "url": target_url})
                else:
                    self.send_json({"status": "error", "message": "Missing url"}, code=400)
                return

            elif path in ("/kill", "/shutdown"):
                self.send_json({"status": "shutting_down"})
                player.stop()
                def shutdown_server():
                    time.sleep(0.3)
                    os._exit(0)
                threading.Thread(target=shutdown_server, daemon=True).start()
                return

            else:
                self.send_json({"status": "error", "message": "Unknown endpoint"}, code=404)
        except Exception as e:
            log_debug(f"do_GET exception: {e}")
            self.send_json({"status": "error", "error": str(e)}, code=500)

class ReusableThreadingServer(ThreadingHTTPServer):
    allow_reuse_address = True

def show_startup_dialog():
    time.sleep(0.3)
    try:
        import ctypes
        import webbrowser
        user32 = ctypes.windll.user32

        MB_OK = 0x00000000
        MB_YESNO = 0x00000004
        MB_ICONINFORMATION = 0x00000040
        MB_ICONWARNING = 0x00000030
        MB_TOPMOST = 0x00040000
        MB_SETFOREGROUND = 0x00010000
        IDYES = 6

        player.detect_devices()

        if player.cable_idx is not None:
            title = "elycde Server — Запущен"
            speaker = player.speaker_name or "По умолчанию"
            cable = player.cable_name or "CABLE Input"
            text = (
                "✅ VB-Audio Virtual Cable успешно обнаружен!\n\n"
                f"• Микрофон в Доту: {cable}\n"
                f"• Наушники (для себя): {speaker}\n\n"
                f"• Папка скриптов: {SCRIPTS_DIR}\n"
                f"• Папка звуков: {SOUNDS_DIR}\n\n"
                "Сервер работает в фоне на 127.0.0.1:8765.\n\n"
                "Напоминание для Доты 2:\n"
                "В 'Настройки' -> 'Звук' -> 'Устройство записи' (микрофон)\n"
                "выберите: «CABLE Output (VB-Audio Virtual Cable)».\n\n"
                "Нажмите ОК и приятной игры!"
            )
            user32.MessageBoxW(0, text, title, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND)
        else:
            title = "elycde Server — VB-Audio Cable не найден!"
            text = (
                "⚠️ Драйвер VB-Audio Virtual Cable не найден в системе!\n\n"
                "Без него звуки не смогут транслироваться в голосовой чат Доты 2.\n\n"
                "Открыть официальный сайт VB-Audio для бесплатного скачивания драйвера прямо сейчас?"
            )
            res = user32.MessageBoxW(0, text, title, MB_YESNO | MB_ICONWARNING | MB_TOPMOST | MB_SETFOREGROUND)
            if res == IDYES:
                try:
                    webbrowser.open("https://vb-audio.com/Cable/")
                except Exception:
                    pass
    except Exception as e:
        log_debug(f"show_startup_dialog error: {e}")

def main():
    init_environment()
    
    # Check if already running
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.settimeout(0.5)
        s.connect(("127.0.0.1", PORT))
        s.close()
        import ctypes
        ctypes.windll.user32.MessageBoxW(
            0,
            "Сервер elycde.exe уже запущен и работает в фоне на порту 8765!",
            "elycde Server",
            0x00000040 | 0x00040000
        )
        return
    except Exception:
        pass

    try:
        log_debug("Starting elycde server on port 8765...")
        log_debug(f"Environment: root='{ROOT_DIR}', scripts='{SCRIPTS_DIR}', vtt='{VTT_DIR}', sounds='{SOUNDS_DIR}'")

        # Initial fast check: download missing scripts right away
        map_script = os.path.join(SCRIPTS_DIR, "MapDrawer.lua")
        set_script = os.path.join(SCRIPTS_DIR, "Settings.lua")
        vis_script = os.path.join(SCRIPTS_DIR, "Visuals.lua")
        vtt_script = os.path.join(SCRIPTS_DIR, "VoiceTrashTalk.lua")
        if not os.path.exists(map_script) or not os.path.exists(set_script) or not os.path.exists(vis_script) or not os.path.exists(vtt_script):
            log_debug("Initial setup: downloading Lua bundle from GitHub...")
            try:
                check_for_updates(force=False)
            except Exception as ex:
                log_debug(f"Initial download error: {ex}")

        server = ReusableThreadingServer(("127.0.0.1", PORT), ElycdeHandler)
        log_debug("Server successfully listening on 127.0.0.1:8765")
        
        threading.Thread(target=show_startup_dialog, daemon=True).start()
        
        cfg = load_config()
        if cfg.get("auto_update", True):
            def auto_update_worker():
                time.sleep(2.0)
                try:
                    check_for_updates(force=False)
                except Exception as ex:
                    log_debug(f"auto_update_worker error: {ex}")
            threading.Thread(target=auto_update_worker, daemon=True).start()

        server.serve_forever()
    except Exception as e:
        log_debug(f"Server fatal error: {e}")
    finally:
        player.stop()

if __name__ == "__main__":
    main()
