"""Send only the qualified release subset through the local Telegram Bot API."""

import html
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import sys
import urllib.parse

from tool.ci_release import ReleaseError, TAG, regular_file, require


def release_files(root, version):
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Invalid release version')
    root = Path(root)
    prefix = 'FlClash-' + version + '-'
    return [regular_file(root / role / (prefix + suffix)) for role, suffix in (
        ('windows-amd64', 'windows-amd64-setup.exe'),
        ('android-final', 'android-arm64-v8a.apk'),
        ('macos-arm64', 'macos-arm64.dmg'),
        ('macos-amd64', 'macos-amd64.dmg'))]


def send_release(token, tag, run_id, files, notes, *, origin='http://localhost:8081'):
    parts = urllib.parse.urlsplit(origin)
    require(parts.scheme == 'http' and parts.hostname in ('localhost', '127.0.0.1')
            and not parts.username and not parts.password and not parts.query
            and not parts.fragment and parts.path in ('', '/'), 'Bot API must be local')
    require(re.fullmatch('[0-9]+:[A-Za-z0-9_-]+', token) and TAG.fullmatch(tag)
            and re.fullmatch('[1-9][0-9]*', str(run_id)) and len(files) == 4, 'Invalid Telegram release input')
    files = [regular_file(path) for path in files]
    require(len(set(files)) == 4, 'Duplicate Telegram release file')
    caption = '\n<b>' + html.escape(tag) + '</b>\n'
    caption += ('\nhttps://github.com/chen08209/FlClash/releases/tag/' + tag + '\n' if '-pre.' not in tag else
                '\nhttps://github.com/chen08209/FlClash/actions/runs/' + str(run_id) + '\n')
    caption += '\n' + notes + '\n'
    media = [{'type': 'document', 'media': 'attach://file' + str(index)} for index in range(1, 5)]
    media[-1].update(caption=caption, parse_mode='HTML')
    boundary = 'release-' + secrets.token_hex(16)
    segments = []
    for name, value in [('chat_id', '@FlClash'), ('media', json.dumps(media))]:
        segments.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode())
    for index, path in enumerate(files, 1):
        require(re.fullmatch('[A-Za-z0-9_.-]+', path.name), 'Unsafe release attachment name')
        segments.extend([(f'--{boundary}\r\nContent-Disposition: form-data; name="file{index}"; '
                          f'filename="{path.name}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode(),
                         path, b'\r\n'])
    segments.append(f'--{boundary}--\r\n'.encode())
    length = sum(segment.stat().st_size if isinstance(segment, Path) else len(segment) for segment in segments)
    connection = http.client.HTTPConnection(parts.hostname, parts.port or 80, timeout=300)
    try:
        connection.putrequest('POST', '/bot' + token + '/sendMediaGroup', skip_accept_encoding=True)
        connection.putheader('Content-Type', 'multipart/form-data; boundary=' + boundary)
        connection.putheader('Content-Length', str(length))
        connection.endheaders()
        for segment in segments:
            if isinstance(segment, Path):
                with segment.open('rb') as stream:
                    while block := stream.read(1024**2):
                        connection.send(block)
            else:
                connection.send(segment)
        response = connection.getresponse()
        body = response.read(1024**2 + 1)
        require(200 <= response.status < 300 and len(body) <= 1024**2, 'Telegram publication rejected')
        payload = json.loads(body)
        require(isinstance(payload, dict) and payload.get('ok') is True, 'Telegram publication rejected')
    except Exception:
        raise ReleaseError('Telegram publication failed') from None
    finally:
        connection.close()


def main():
    try:
        root = Path(os.environ['CI_ARTIFACT_ROOT'])
        tag = os.environ['TAG']
        require(TAG.fullmatch(tag), 'Invalid tag')
        version = tag.removeprefix('v').split('-pre.')[0]
        notes = regular_file(root / 'notes/telegram.md')
        require(notes.stat().st_size <= 1024**2, 'Excessive Telegram notes')
        send_release(os.environ['TELEGRAM_BOT_TOKEN'], tag, os.environ['RUN_ID'],
                     release_files(root, version), notes.read_text())
    except Exception:
        print('Telegram publication failed', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
