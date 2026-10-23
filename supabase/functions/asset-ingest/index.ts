/** Internal stock import only; no user original can be read through this API.
 * SQL must first reserve the exact stock path. Existing active assets cannot be
 * overwritten. No service key is ever returned to import tools or the app. */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const reply = (status: number, body: object) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async request => {
  if (!["PUT", "POST"].includes(request.method)) return reply(405, { error: "method_not_allowed" });
  const token = request.headers.get("x-mefrion-worker");
  if (!token || token.length < 32 || token.length > 256) return reply(401, { error: "authentication_required" });
  const server = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const auth = await server.rpc("mefrion_cloud_worker_authorize", { p_token: token });
  if (auth.error || auth.data !== true) return reply(401, { error: "authentication_required" });
  if (request.method === "POST") {
    if (Number(request.headers.get("content-length")) > 5_500_000) return reply(413, { error: "batch_size" });
    try {
      const text = await request.text();
      if (text.length > 5_500_000) return reply(413, { error: "batch_size" });
      const items: { path: string; bytes: string }[] = JSON.parse(text).items;
      if (!Array.isArray(items) || items.length < 1 || items.length > 20 || items.some(i => !/^pexels-[0-9]+\.jpg$/.test(i.path) || typeof i.bytes !== "string" || i.bytes.length > 270000)) return reply(400, { error: "batch_invalid" });
      const paths = items.map(i => i.path);
      if (new Set(paths).size !== paths.length) return reply(400, { error: "batch_invalid" });
      const allowed = await server.rpc("mefrion_cloud_reference_ingest_allowed", { p_paths: paths });
      if (allowed.error || allowed.data?.length !== items.length) return reply(403, { error: "reservation_required" });
      const uploaded: string[] = [], failed: string[] = [];
      for (let start = 0; start < items.length; start += 4) {
        await Promise.all(items.slice(start, start + 4).map(async item => {
          const bytes = Uint8Array.from(atob(item.bytes), c => c.charCodeAt(0));
          if (bytes.length > 200000 || bytes[0] !== 255 || bytes[1] !== 216) { failed.push(item.path); return; }
          const result = await server.storage.from("reference-thumbnails").upload(item.path, bytes, { contentType: "image/jpeg", upsert: true, cacheControl: "0" });
          (result.error ? failed : uploaded).push(item.path);
        }));
      }
      return reply(200, { uploaded, failed });
    } catch { return reply(400, { error: "batch_invalid" }); }
  }
  const params = new URL(request.url).searchParams, bucket = params.get("bucket"), path = params.get("path");
  if (!bucket || !path || !/^[a-zA-Z0-9/-]+\.(jpg|mp4)$/.test(path) || path.includes("..")) return reply(400, { error: "path_invalid" });
  const before = await server.rpc("mefrion_cloud_ingest_allowed", { p_bucket: bucket, p_path: path });
  if (before.error || before.data !== true) return reply(403, { error: "reservation_required" });
  const video = path.endsWith(".mp4"), contentType = video ? "video/mp4" : "image/jpeg";
  if (request.headers.get("content-type") !== contentType || (video && bucket !== "family-originals")) return reply(415, { error: "media_type" });
  const max = bucket === "reference-thumbnails" ? 200000 : (video ? 49 : 20) * 1024 * 1024;
  if (Number(request.headers.get("content-length")) > max) return reply(413, { error: "image_size" });
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > max || (video ? new TextDecoder().decode(bytes.subarray(4, 8)) !== "ftyp" : bytes[0] !== 255 || bytes[1] !== 216)) return reply(400, { error: "media_invalid" });
  const uploaded = await server.storage.from(bucket).upload(path, bytes, { contentType, upsert: true, cacheControl: "0" });
  if (uploaded.error) return reply(503, { error: "upload_failed" });
  const after = await server.rpc("mefrion_cloud_ingest_allowed", { p_bucket: bucket, p_path: path });
  if (after.error || after.data !== true) {
    // An already activated reference is immutable. A private reservation revoked
    // during this write is removed rather than leaving a late original behind.
    if (bucket === "family-originals") await server.storage.from(bucket).remove([path]);
    return reply(409, { error: "reservation_changed" });
  }
  return reply(200, { uploaded: true });
});
