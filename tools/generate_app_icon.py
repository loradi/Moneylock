from pathlib import Path
import struct
import zlib

SIZE = 1024
RED = (186, 26, 26)
DARK = (142, 16, 20)
WHITE = (255, 255, 255)

def rounded_rect(px, x0, y0, x1, y1, radius, color):
    for y in range(max(0, y0), min(SIZE, y1)):
        for x in range(max(0, x0), min(SIZE, x1)):
            dx = max(x0 + radius - x, 0, x - (x1 - radius - 1))
            dy = max(y0 + radius - y, 0, y - (y1 - radius - 1))
            if dx * dx + dy * dy <= radius * radius:
                px[y][x] = color

def rect(px, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                px[y][x] = color

def circle(px, cx, cy, radius, color):
    r2 = radius * radius
    for y in range(max(0, cy-radius), min(SIZE, cy+radius+1)):
        for x in range(max(0, cx-radius), min(SIZE, cx+radius+1)):
            if (x-cx)*(x-cx) + (y-cy)*(y-cy) <= r2:
                px[y][x] = color

def png(path, px):
    raw = b''.join(b'\x00' + bytes(v for rgb in row for v in rgb) for row in px)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n'
    data += chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(raw, 9))
    data += chunk(b'IEND', b'')
    Path(path).write_bytes(data)

px = [[RED for _ in range(SIZE)] for _ in range(SIZE)]
rounded_rect(px, 236, 198, 788, 826, 96, DARK)
rounded_rect(px, 276, 254, 748, 770, 76, WHITE)
rect(px, 338, 330, 686, 390, RED)
rect(px, 338, 330, 408, 390, RED)
circle(px, 512, 512, 87, RED)
circle(px, 512, 512, 20, WHITE)
rect(px, 503, 526, 521, 600, WHITE)
png('/tmp/moneylock-icon.png', px)
