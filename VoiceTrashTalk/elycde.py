import os
import sys
import json
import random
import time
import threading
import hashlib
import urllib.request
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import numpy as np
import sounddevice as sd
import miniaudio

PORT = 8765

if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

PARENT_DIR = os.path.dirname(BASE_DIR)
SOUNDS_DIR = os.path.join(BASE_DIR, "sounds")
LOG_FILE = os.path.join(BASE_DIR, "elycde.log")
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")

DEFAULT_CONFIG = {
    "repo": "elycde/elycde-scripts",
    "branch": "main",
    "auto_update": True,
    "last_commit": ""
}

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
        req = urllib.request.Request(url, headers={"User-Agent": "elycde-updater/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return resp.read()
    except Exception as e:
        log_debug(f"download_url error ({url}): {e}")
    return None

def check_for_updates(force=False):
    cfg = load_config()
    repo = cfg.get("repo", "elycde/elycde-scripts").strip()
    branch = cfg.get("branch", "main").strip()
    if not repo:
        return False, [], "Репозиторий не указан в config.json"

    updated_files = []
    exe_updated = False

    # Check commit SHA from GitHub API (best effort)
    api_url = f"https://api.github.com/repos/{repo}/commits/{branch}"
    remote_sha = None
    try:
        req = urllib.request.Request(api_url, headers={"User-Agent": "elycde-updater/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                data = json.loads(resp.read().decode("utf-8"))
                remote_sha = data.get("sha", "")
    except Exception:
        pass

    last_sha = cfg.get("last_commit", "")
    if not force and remote_sha and last_sha and remote_sha == last_sha:
        log_debug(f"Already on latest commit: {remote_sha[:7]}")
        return False, [], "Установлена последняя версия!"

    # 1. Update VoiceTrashTalk.lua
    vtt_url = f"https://raw.githubusercontent.com/{repo}/{branch}/VoiceTrashTalk.lua"
    vtt_local = os.path.join(PARENT_DIR, "VoiceTrashTalk.lua")
    content = download_url(vtt_url)
    if content and len(content) > 100:
        local_hash = get_file_hash(vtt_local)
        remote_hash = hashlib.sha256(content).hexdigest()
        if local_hash != remote_hash:
            try:
                with open(vtt_local, "wb") as f:
                    f.write(content)
                updated_files.append("VoiceTrashTalk.lua")
                log_debug("Updated VoiceTrashTalk.lua from GitHub")
            except Exception as e:
                log_debug(f"Failed to write VoiceTrashTalk.lua: {e}")

    # 2. Update elycde.lua (Map Drawer)
    ely_url = f"https://raw.githubusercontent.com/{repo}/{branch}/elycde.lua"
    ely_local = os.path.join(PARENT_DIR, "elycde.lua")
    content = download_url(ely_url)
    if content and len(content) > 100:
        local_hash = get_file_hash(ely_local)
        remote_hash = hashlib.sha256(content).hexdigest()
        if local_hash != remote_hash:
            try:
                with open(ely_local, "wb") as f:
                    f.write(content)
                updated_files.append("elycde.lua")
                log_debug("Updated elycde.lua from GitHub")
            except Exception as e:
                log_debug(f"Failed to write elycde.lua: {e}")

    # 3. Update elycde.exe (Self-update)
    if getattr(sys, 'frozen', False):
        exe_url = f"https://raw.githubusercontent.com/{repo}/{branch}/VoiceTrashTalk/elycde.exe"
        exe_local = sys.executable
        content = download_url(exe_url, timeout=30)
        if content and len(content) > 1000000:
            local_hash = get_file_hash(exe_local)
            remote_hash = hashlib.sha256(content).hexdigest()
            if local_hash != remote_hash:
                new_exe = exe_local + ".new"
                try:
                    with open(new_exe, "wb") as f:
                        f.write(content)
                    exe_updated = True
                    log_debug("Downloaded new elycde.exe. Spawning self-updater...")

                    updater_bat = os.path.join(BASE_DIR, "updater.bat")
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
                    subprocess.Popen(["cmd.exe", "/c", updater_bat], cwd=BASE_DIR, creationflags=0x08000000 if os.name == 'nt' else 0)
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
        self._stop_event = threading.Event()
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
        decoded = miniaudio.decode_file(filepath)
        sr = decoded.sample_rate
        ch = decoded.nchannels
        samples = np.array(decoded.samples, dtype=np.float32) / 32768.0
        audio_data = samples.reshape(-1, ch)
        duration_ms = int((decoded.num_frames / sr) * 1000)
        return audio_data, sr, duration_ms

    def play(self, filepath, speaker_vol=80, mic_vol=100, only_speaker=False, only_mic=False):
        self.stop()
        self._stop_event.clear()

        audio_data, sr, duration_ms = self.load_audio(filepath)

        s_vol = max(0.0, min(1.0, float(speaker_vol) / 100.0))
        m_vol = max(0.0, min(1.0, float(mic_vol) / 100.0))

        cable_audio = audio_data * m_vol
        speaker_audio = audio_data * s_vol

        use_cable = (self.cable_idx is not None) and (not only_speaker) and (m_vol > 0.001)
        use_speaker = (self.speaker_idx is not None) and (not only_mic) and (s_vol > 0.001)

        def play_stream(device, data):
            try:
                channels = data.shape[1] if len(data.shape) > 1 else 1
                with sd.OutputStream(device=device, samplerate=sr, channels=channels) as stream:
                    chunk_size = 2048
                    pos = 0
                    total_len = len(data)
                    while pos < total_len and not self._stop_event.is_set():
                        chunk = data[pos : pos + chunk_size]
                        stream.write(chunk)
                        pos += chunk_size
            except Exception as e:
                log_debug(f"play_stream error (device={device}): {e}")

        threads = []
        if use_cable:
            t_cable = threading.Thread(target=play_stream, args=(self.cable_idx, cable_audio), daemon=True)
            threads.append(t_cable)
            t_cable.start()

        if use_speaker:
            t_speaker = threading.Thread(target=play_stream, args=(self.speaker_idx, speaker_audio), daemon=True)
            threads.append(t_speaker)
            t_speaker.start()

        self.is_playing = len(threads) > 0
        return True, duration_ms, use_cable, use_speaker

    def stop(self):
        self._stop_event.set()
        try:
            sd.stop()
        except Exception:
            pass
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
                    candidate = os.path.join(SOUNDS_DIR, specific_file.replace("/", "\\"))
                    if os.path.exists(candidate):
                        target_path = candidate
                    else:
                        for f in get_sound_files():
                            if os.path.basename(f).lower() == specific_file.lower():
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
                    
                    try:
                        subprocess.Popen(f'explorer.exe "{SOUNDS_DIR}"', shell=True)
                    except Exception:
                        os.startfile(SOUNDS_DIR)

                    log_debug(f"Opened sounds folder: {SOUNDS_DIR}")
                    self.send_json({"status": "opened", "path": SOUNDS_DIR})
                except Exception as e:
                    log_debug(f"open_folder error: {e}")
                    self.send_json({"status": "error", "message": str(e)}, code=500)
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
                f"• Выход в Доту (микрофон): {cable}\n"
                f"• Наушники (для себя): {speaker}\n\n"
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
    if not os.path.exists(SOUNDS_DIR):
        os.makedirs(SOUNDS_DIR, exist_ok=True)
    
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
        server = ReusableThreadingServer(("127.0.0.1", PORT), ElycdeHandler)
        log_debug("Server successfully listening on 127.0.0.1:8765")
        
        # Diagnostic dialog
        threading.Thread(target=show_startup_dialog, daemon=True).start()
        
        # Background auto-update check after 3 seconds
        cfg = load_config()
        if cfg.get("auto_update", True):
            def auto_update_worker():
                time.sleep(3.0)
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
