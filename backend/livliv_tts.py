"""Loopback, single-render Qwen3-TTS worker for the author's LivLiv room."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from livliv import ROLES

TOOLS = Path(os.environ.get('DENTSTUDY_TTS_TOOLS', '/opt/dentstudy-livliv-tts/2edb35f/build'))
MODELS = Path(os.environ.get('DENTSTUDY_TTS_MODELS', '/opt/dentstudy-livliv-tts/models'))
REFS = Path(__file__).resolve().parent / 'livliv_refs'
VOICES = Path(os.environ.get('DENTSTUDY_TTS_VOICES', '/opt/dentstudy-current/mobile/web/livliv/voices'))


def synthesize(role, text):
    lines = json.loads((VOICES / 'lines.json').read_text())
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / 'speech.wav'
        transcript = Path(tmp) / 'reference.txt'
        transcript.write_text(lines[role])
        subprocess.run([
            str(TOOLS / 'qwen-tts'), '--model', str(MODELS / 'qwen-talker-0.6b-base-Q4_K_M.gguf'),
            '--codec', str(MODELS / 'qwen-tokenizer-12hz-Q4_K_M.gguf'),
            '--ref-spk', str(REFS / f'{role}.spk'), '--ref-rvq', str(REFS / f'{role}.rvq'),
            '--ref-text', str(transcript),
            '--lang', 'Chinese', '--codec-chunk-dur', '5', '--max-new', str(max(100, len(text) * 8)), '-o', str(out),
        ], input=text.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
           timeout=240, check=True, env={**os.environ, 'DENTSTUDY_TTS_ONESHOT': '1'})
        data = out.read_bytes()
        if not (2000 < len(data) < 2_000_000 and data.startswith(b'RIFF') and data[8:12] == b'WAVE'):
            raise ValueError('invalid synthesized audio')
        return base64.b64encode(data).decode('ascii')


class RenderCache:
    def __init__(self, render=synthesize):
        self.render = render
        self.lock = threading.Lock()
        self.active = None
        self.entries = {}

    def render_one(self, key, role, text):
        result = {'status': 'failed'}
        try:
            result = {'status': 'ready', 'audio': self.render(role, text)}
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            pass
        finally:
            with self.lock:
                self.active = None
                self.entries[key] = (time.monotonic(), result)

    def get(self, role, text):
        key = hashlib.sha256((role + '\0' + text).encode()).digest()
        with self.lock:
            now = time.monotonic()
            self.entries = {k: v for k, v in self.entries.items() if now - v[0] < 300}
            if key in self.entries:
                result = self.entries[key][1]
                if result['status'] == 'failed':
                    self.entries.pop(key)
                return result
            if self.active is None:
                if len(self.entries) >= 24:
                    self.entries.pop(next(iter(self.entries)))
                self.active = key
                threading.Thread(target=self.render_one, args=(key, role, text), daemon=True).start()
            return {'status': 'pending'}


cache = RenderCache()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if self.path != '/render' or not 0 < size <= 2048:
                raise ValueError()
            data = json.loads(self.rfile.read(size))
            role, text = data['role'], data['text']
            if role not in ROLES or not isinstance(text, str) or not 0 < len(text) <= 40:
                raise ValueError()
            body = json.dumps(cache.get(role, text)).encode()
        except (KeyError, TypeError, ValueError):
            self.send_error(400)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8796), Handler).serve_forever()
