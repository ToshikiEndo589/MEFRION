import { imageDerivative, jpegDimensions, videoDerivative } from "./media.ts";

function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw new Error(message); }
function rejects(fn: () => unknown) { let failed = false; try { fn(); } catch { failed = true; } assert(failed, "unsafe media was accepted"); }
const concat = (...arrays: Uint8Array[]) => { const result = new Uint8Array(arrays.reduce((n, a) => n + a.length, 0)); let at = 0; for (const array of arrays) { result.set(array, at); at += array.length; } return result; };
function box(type: string, bytes: Uint8Array) { const result = new Uint8Array(bytes.length + 8); new DataView(result.buffer).setUint32(0, result.length); result.set(new TextEncoder().encode(type), 4); result.set(bytes, 8); return result; }
function movie(seconds: number, metadata = true): Uint8Array {
  const mvhd = new Uint8Array(100); const v = new DataView(mvhd.buffer); v.setUint32(4, 12345); v.setUint32(12, 1000); v.setUint32(16, seconds * 1000);
  const handler = new Uint8Array(32); handler.set(new TextEncoder().encode("vide"), 8);
  const stsd = new Uint8Array(8); new DataView(stsd.buffer).setUint32(4, 1);
  const trak = box("trak", box("mdia", concat(box("hdlr", handler), box("minf", box("stbl", box("stsd", concat(stsd, box("avc1", new Uint8Array(78)))))))));
  return concat(box("ftyp", new TextEncoder().encode("mp42\0\0\0\0mp42isom")), box("mdat", new Uint8Array(64)), box("moov", concat(box("mvhd", mvhd), trak, ...(metadata ? [box("udta", new TextEncoder().encode("PRIVATE-LOCATION"))] : []))));
}
Deno.test("invalid/oversized JPEG rejected before decoder allocation", async () => {
  let rejected = 0;
  for (const bytes of [new Uint8Array(50), new Uint8Array(21 * 1024 * 1024)]) {
    try { await imageDerivative(bytes); } catch { rejected++; }
  }
  assert(rejected === 2);
  const header = new Uint8Array([255,216,255,192,0,8,8,255,255,255,255,3]); rejects(() => jpegDimensions(header));
});
Deno.test("video rejects invalid containers and durations beyond five minutes", () => {
  rejects(() => videoDerivative(new Uint8Array(64)));
  rejects(() => videoDerivative(movie(301)));
});
Deno.test("video metadata erased and moov moved before mdat", () => {
  const output = videoDerivative(movie(5)), text = new TextDecoder().decode(output);
  assert(!text.includes("PRIVATE-LOCATION"));
  assert(text.indexOf("moov") < text.indexOf("mdat"));
  assert(output.length === movie(5).length);
});
Deno.test("JPEG derivative has bounded dimensions and no original EXIF", async () => {
  const path = Deno.env.get("MEFRION_IMAGE_TEST_FIXTURE");
  if (!path) return;
  const output = await imageDerivative(await Deno.readFile(path));
  const size = jpegDimensions(output);
  assert(size.width <= 1200 && size.height <= 1200);
  assert(!new TextDecoder().decode(output).includes("PRIVATE-MEFRION-METADATA"));
});
