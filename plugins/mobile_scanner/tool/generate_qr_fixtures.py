"""Synthetic fixtures: qrcode 8.2 (BSD), independent of the ZXing reader."""
from pathlib import Path
import json
import struct
import zlib
import qrcode

out = Path(__file__).resolve().parents[1] / 'android/src/test/resources/qr'
values = {
    'url': 'https://example.invalid/subscription?token=SYNTHETIC-T09',
    'install': 'flclash://install-config?url=https%3A%2F%2Fexample.invalid%2Fsub%3Ftoken%3DSYNTHETIC',
    'unicode': 'https://example.invalid/路径?token=合成',
    'long': 'https://example.invalid/sub?token=' + 'X' * (2048 - len('https://example.invalid/sub?token=')),
    'text': 'synthetic QR text, not a subscription',
}

def png(matrix, scale=5, orientation=None):
    width = len(matrix[0]) * scale
    rows = b''.join(b'\0' + bytes(0 if x else 255 for x in row for _ in range(scale))
                    for row in matrix for _ in range(scale))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, len(matrix)*scale, 8, 0, 0, 0, 0))
            + (chunk(b'eXIf', b'II' + struct.pack('<HIHHHIHHI', 42, 8, 1, 0x0112, 3, 1, orientation, 0, 0)) if orientation else b'')
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

for name, value in values.items():
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L, border=4)
    code.add_data(value.encode('utf-8'), optimize=0)
    code.make()
    (out / (name + '.png')).write_bytes(png(code.get_matrix()))
(out / 'expected.json').write_text(json.dumps(values, ensure_ascii=False, indent=2) + '\n')

def matrix(value):
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L, border=4)
    code.add_data(value.encode('utf-8'), optimize=0)
    code.make()
    return code.get_matrix()

left, right = matrix(values['text']), matrix(values['url'])
height = max(len(left), len(right))
mixed = [[False] * (len(left[0]) + 12 + len(right[0])) for _ in range(height)]
for code, x_offset in [(left, 0), (right, len(left[0]) + 12)]:
    for y, row in enumerate(code):
        mixed[y][x_offset:x_offset+len(row)] = row
(out / 'multiple.png').write_bytes(png(mixed))
for orientation in [2, 6]:
    (out / f'exif_{orientation}.png').write_bytes(png(right, orientation=orientation))
