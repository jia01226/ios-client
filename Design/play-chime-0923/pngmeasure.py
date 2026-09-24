import zlib, struct, sys

def load_alpha(path):
    data = open(path,'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8; idat = b''; w=h=bd=ct=None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        body = data[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w,h,bd,ct,comp,filt,inter = struct.unpack('>IIBBBBB', body)
            assert bd==8 and ct==6 and inter==0, (bd,ct,inter)
        elif typ == b'IDAT': idat += body
        elif typ == b'IEND': break
        pos += 12+ln
    raw = zlib.decompress(idat)
    bpp = 4; stride = w*bpp
    alpha = [[0]*w for _ in range(h)]
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(bpp, stride): line[i] = (line[i] + line[i-bpp]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-bpp] if i >= bpp else 0
                b = prev[i]; c = prev[i-bpp] if i >= bpp else 0
                pa = abs(b-c); pb = abs(a-c); pc = abs(a+b-2*c)
                pr = a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i] = (line[i] + pr) & 255
        row = alpha[y]
        for x in range(w): row[x] = line[x*4+3]
        prev = line
    return w, h, alpha


# 用法：量一张透明底素材里各个部件的位置。
#   from pngmeasure import load_alpha
#   w, h, a = load_alpha("素材.png")
#   逐列统计 a[y][x] > 40 的像素，能分出并排的几串；
#   逐行统计宽度，宽度骤降到个位数的地方是挂线，宽的地方是坠子。
#
# 2026-09-23 玩页风铃就是这么量出来的：三串的金环在原图里分别在 y=124 / 67 / 92，
# 靠眼睛看缩略图估，连错四轮。
