import zlib from "node:zlib";

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf: Buffer): number {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, data: Buffer): Buffer {
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const out = Buffer.alloc(8 + data.length + 4);
  out.writeUInt32BE(data.length, 0);
  body.copy(out, 4);
  out.writeUInt32BE(crc32(body), 4 + body.length);
  return out;
}

/** Encode raw RGB (w*h*3 bytes) as a PNG, nearest-neighbour upscaled by `scale`. */
export function encodePng(rgb: Buffer, w: number, h: number, scale = 1): Buffer {
  if (rgb.length !== w * h * 3) throw new Error(`rgb size mismatch: got ${rgb.length}, expected ${w * h * 3}`);
  const W = w * scale;
  const H = h * scale;
  const stride = W * 3 + 1;
  const raw = Buffer.alloc(stride * H); // filter byte 0 per row
  for (let y = 0; y < H; y++) {
    const src = Math.floor(y / scale) * w * 3;
    let o = y * stride + 1;
    for (let x = 0; x < W; x++) {
      const s = src + Math.floor(x / scale) * 3;
      raw[o++] = rgb[s];
      raw[o++] = rgb[s + 1];
      raw[o++] = rgb[s + 2];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0);
  ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** Plugin "rgb" payload: u16 width, u16 height, u8 scale (big endian), then w*h*3 RGB bytes. */
export function pngFromRgbPayload(payload: Buffer): Buffer {
  if (payload.length < 5) throw new Error("rgb payload too short");
  const w = payload.readUInt16BE(0);
  const h = payload.readUInt16BE(2);
  const scale = payload[4];
  return encodePng(payload.subarray(5), w, h, scale);
}
