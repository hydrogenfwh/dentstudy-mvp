"""Author-room credentials and speech tickets. Neither contains the login bearer."""
import base64
import hashlib
import hmac
import json
import re
import secrets
import time
from http.cookies import CookieError, SimpleCookie

ROLES = {
    'p01': 'Kujira', 'p02': 'Kujira Q', 'p03': 'Pen', 'char06': 'Aoi',
    'char07': 'Sora', 'd01': 'Yui', 'd02': 'Leo', 'd03': 'Nana',
    'd03ft': 'Nana 精修', 'k01': 'Sena', 'k02': 'Elio', 'q02': 'Mochi',
    'q03': 'Kotaro', 's01': 'Hana', 'v04': 'Kai', 'v05': 'Lilith',
    'v06': 'Usa', 'v07': 'Stella', 'w01': 'Max',
}
COOKIE = 'dentstudy_livliv'
COOKIE_FLAGS = '; Path=/api/v1/assistant/; HttpOnly; Secure; SameSite=Strict'
FALLBACK_KEY = secrets.token_bytes(32)


def tag(key, *values):
    message = json.dumps(values, ensure_ascii=False, separators=(',', ':')).encode()
    return base64.urlsafe_b64encode(hmac.digest(key or FALLBACK_KEY, message, 'sha256')).decode().rstrip('=')


def room_cookie(key, bearer=None):
    if not bearer:
        return f'{COOKIE}=; Max-Age=0{COOKIE_FLAGS}'
    digest = hashlib.sha256(bearer.encode()).hexdigest()
    return f'{COOKIE}={digest}.{tag(key, "room", digest)}; Max-Age=2592000{COOKIE_FLAGS}'


def session_digest(key, header):
    cookie = SimpleCookie()
    try:
        cookie.load(header)
        digest, signature = cookie[COOKIE].value.split('.')
        if re.fullmatch('[0-9a-f]{64}', digest) and secrets.compare_digest(signature, tag(key, 'room', digest)):
            return digest
    except (CookieError, KeyError, ValueError, TypeError):
        pass
    return None


def speech_ticket(key, uid, role, reply):
    expiry = int(time.time()) + 3600
    return f'{expiry}.{tag(key, "speech", uid, role, reply, expiry)}'


def check_ticket(key, ticket, uid, role, reply):
    if not isinstance(ticket, str) or not re.fullmatch(r'[0-9]{10}\.[A-Za-z0-9_-]{43}', ticket):
        return False
    expiry, signature = ticket.split('.')
    return int(expiry) >= time.time() and secrets.compare_digest(
        signature, tag(key, 'speech', uid, role, reply, int(expiry)))


def phrases(text):
    # Prefer sentence and clause boundaries, while keeping numeric expressions intact.
    parts = []
    while len(text) > 40:
        ends = [m.end() for m in re.finditer(r'[。！？；，、！\n]|[.!?;,:](?=\s)', text[:40])]
        end = next((n for n in ends if n >= 12), ends[-1] if ends else 40)
        if text[:end].strip():
            parts.append(text[:end].strip())
        text = text[end:].lstrip()
    if text.strip():
        parts.append(text.strip())
    return parts
