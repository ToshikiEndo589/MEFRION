import { ImageMagick, initializeImageMagick, MagickFormat, MagickGeometry, MagickReadSettings } from "npm:@imagemagick/magick-wasm@0.0.45";

let initialized: Promise<void> | undefined;
async function initializeDecoder(): Promise<void> {
  if (!initialized) initialized = (async () => {
    // Pin both version and binary hash. The runtime has no native subprocesses;
    // fetching this public WASM module does not send photos to a third party.
    const local = Deno.env.get("MEFRION_MAGICK_WASM_PATH");
    const bytes = local ? await Deno.readFile(local) : new Uint8Array(await (await fetch("https://cdn.jsdelivr.net/npm/@imagemagick/magick-wasm@0.0.45/dist/x86/magick.wasm", { signal: AbortSignal.timeout(30000) })).arrayBuffer());
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), v => v.toString(16).padStart(2, "0")).join("");
    if (hash !== "54629cbcf06dd10db38b4d87fa6ab241b248c09c94f2d9689506e5f994ac5f0c") throw new MediaError("decoder_integrity");
    await initializeImageMagick(bytes);
  })().catch(error => { initialized = undefined; throw error; });
  return initialized;
}

export class MediaError extends Error {
  constructor(public code: string) { super(code); }
}

export function jpegDimensions(bytes: Uint8Array): { width: number; height: number } {
  if (bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216) throw new MediaError("jpeg_invalid");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let pos = 2;
  while (pos + 4 <= bytes.length) {
    if (bytes[pos++] !== 255) throw new MediaError("jpeg_invalid");
    while (bytes[pos] === 255) pos++;
    const marker = bytes[pos++];
    if (marker === 218 || marker === 217) break;
    const length = view.getUint16(pos);
    if (length < 2 || pos + length > bytes.length) throw new MediaError("jpeg_invalid");
    if ([192, 193, 194].includes(marker)) {
      if (length < 8) throw new MediaError("jpeg_invalid");
      const height = view.getUint16(pos + 3), width = view.getUint16(pos + 5);
      if (!width || !height || width > 4000 || height > 4000 || width * height > 16_000_000) throw new MediaError("image_dimensions");
      return { width, height };
    }
    pos += length;
  }
  throw new MediaError("jpeg_invalid");
}

/** Decode and re-encode pixels; EXIF/GPS/ICC/comments are never copied. */
export async function imageDerivative(bytes: Uint8Array): Promise<Uint8Array> {
  if (!bytes.length || bytes.length > 20 * 1024 * 1024) throw new MediaError("image_size");
  jpegDimensions(bytes); // Bound allocation before entering the WASM decoder.
  try {
    await initializeDecoder();
    const settings = new MagickReadSettings({ format: MagickFormat.Jpeg });
    settings.setDefine(MagickFormat.Jpeg, "size", "1200x1200");
    return ImageMagick.read(bytes, settings, image => {
      image.autoOrient();
      const geometry = new MagickGeometry(1200, 1200); geometry.greater = true;
      image.resize(geometry); image.strip(); image.quality = 85;
      return image.write(MagickFormat.Jpeg, data => data.slice());
    });
  } catch (error) {
    if (error instanceof MediaError) throw error;
    throw new MediaError("image_decode");
  }
}

type Box = { start: number; size: number; header: number; type: string };
const text = (bytes: Uint8Array, pos: number) => String.fromCharCode(...bytes.subarray(pos, pos + 4));
function boxes(bytes: Uint8Array, start: number, end: number): Box[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), result: Box[] = [];
  for (let pos = start; pos < end;) {
    if (pos + 8 > end || result.length > 100000) throw new MediaError("video_container");
    let size = view.getUint32(pos), header = 8;
    if (size === 1) {
      if (pos + 16 > end) throw new MediaError("video_container");
      const large = view.getBigUint64(pos + 8);
      if (large > BigInt(bytes.length)) throw new MediaError("video_container");
      size = Number(large); header = 16;
    } else if (size === 0) size = end - pos;
    if (size < header || pos + size > end) throw new MediaError("video_container");
    result.push({ start: pos, size, header, type: text(bytes, pos + 4) }); pos += size;
  }
  return result;
}

/** iOS already exports H.264/HEVC + AAC at <=5 min/49MB. The server validates
 * the actual container, strips identifying metadata and moves moov to the front.
 * It never trusts the duration/type declared by the client or copies metadata.
 * No ffmpeg subprocess, Mac or always-on paid transcoder is required. */
export function videoDerivative(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 32 || bytes.length > 50 * 1024 * 1024) throw new MediaError("video_size");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const roots = boxes(bytes, 0, bytes.length), moovs = roots.filter(b => b.type === "moov");
  if (roots[0]?.type !== "ftyp" || roots[0].size < 16 || moovs.length !== 1 || !roots.some(b => b.type === "mdat")) throw new MediaError("video_container");
  if (roots.some(b => ["moof", "sidx", "mfra"].includes(b.type))) throw new MediaError("video_fragmented");
  const offsets: Box[] = [];
  let duration = 0, videoTracks = 0;
  const blank = (box: Box) => {
    bytes.set(new TextEncoder().encode("free"), box.start + 4);
    bytes.fill(0, box.start + box.header, box.start + box.size);
  };
  const walk = (start: number, end: number, depth: number) => {
    if (depth > 12) throw new MediaError("video_container");
    for (const box of boxes(bytes, start, end)) {
      const p = box.start + box.header;
      if (["udta", "meta", "uuid", "loci", "free", "skip"].includes(box.type) || box.type.charCodeAt(0) === 169) { blank(box); continue; }
      if (["moov", "trak", "mdia", "minf", "stbl", "edts", "dinf"].includes(box.type)) { walk(p, box.start + box.size, depth + 1); continue; }
      if (["mvhd", "mdhd", "tkhd"].includes(box.type)) {
        const version = bytes[p];
        if (version > 1 || p + (version === 1 ? 36 : 24) > box.start + box.size) throw new MediaError("video_container");
        bytes.fill(0, p + 4, p + (version === 1 ? 20 : 12));
        if (box.type === "mvhd") {
          const scale = view.getUint32(p + (version === 1 ? 20 : 12));
          const ticks = version === 1 ? Number(view.getBigUint64(p + 24)) : view.getUint32(p + 16);
          duration = scale ? ticks / scale : 0;
        }
        if (box.type === "tkhd") {
          const width = view.getUint32(box.start + box.size - 8) / 65536;
          const height = view.getUint32(box.start + box.size - 4) / 65536;
          if (width > 1920 || height > 1920) throw new MediaError("video_dimensions");
        }
      } else if (box.type === "hdlr") {
        if (p + 24 > box.start + box.size) throw new MediaError("video_container");
        const handler = text(bytes, p + 8);
        if (handler === "vide") videoTracks++;
        if (!["vide", "soun", "dhlr", "alis", "url "].includes(handler)) throw new MediaError("video_track");
        bytes.fill(0, p + 24, box.start + box.size); // human-readable handler name
      } else if (box.type === "stsd") {
        if (p + 8 > box.start + box.size) throw new MediaError("video_container");
        const entries = boxes(bytes, p + 8, box.start + box.size);
        if (!entries.length || entries.some(b => !["avc1", "hvc1", "hev1", "mp4a"].includes(b.type))) throw new MediaError("video_codec");
      } else if (["stco", "co64"].includes(box.type)) offsets.push(box);
      else if (box.type === "mvex") throw new MediaError("video_fragmented");
    }
  };
  walk(0, bytes.length, 0);
  if (!(duration > 0 && duration <= 300.1) || videoTracks !== 1) throw new MediaError("video_duration_or_track");
  // Reorder complete boxes and adjust chunk offsets without recompressing any
  // audio/video sample. Box lengths and file length remain unchanged.
  const order = [roots[0], moovs[0], ...roots.slice(1).filter(b => b !== moovs[0])];
  let destination = 0;
  const positions = order.map(box => { const result = { ...box, destination }; destination += box.size; return result; });
  for (const box of offsets) {
    const p = box.start + box.header, stride = box.type === "stco" ? 4 : 8;
    if (p + 8 > box.start + box.size) throw new MediaError("video_offsets");
    const count = view.getUint32(p + 4);
    if (count > 100000 || p + 8 + count * stride !== box.start + box.size) throw new MediaError("video_offsets");
    for (let i = 0; i < count; i++) {
      const index = p + 8 + i * stride;
      const old = stride === 4 ? view.getUint32(index) : Number(view.getBigUint64(index));
      const target = positions.find(b => b.type === "mdat" && old >= b.start + b.header && old < b.start + b.size);
      if (!target) throw new MediaError("video_offsets");
      const updated = old + target.destination - target.start;
      if (stride === 4) view.setUint32(index, updated); else view.setBigUint64(index, BigInt(updated));
    }
  }
  const output = new Uint8Array(bytes.length);
  for (const box of positions) output.set(bytes.subarray(box.start, box.start + box.size), box.destination);
  return output;
}
