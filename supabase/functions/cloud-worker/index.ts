import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { imageDerivative, MediaError, videoDerivative } from "../_shared/media.ts";

const headers = { "Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
const reply = (status: number, body: object) => new Response(JSON.stringify(body), { status, headers });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
type Job = { id: string; kind: string; entity_id: string; path: string; payload: Record<string, unknown> };

export function safeObjectPath(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 512 && !value.startsWith("/") && !value.split("/").some(p => !p || p === "." || p === "..") && !/[\x00-\x1f\\]/.test(value);
}

export async function authorized(received: string | null, expected: string): Promise<boolean> {
  if (!received || !expected || expected.length < 32) return false;
  const hash = async (value: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([hash(received), hash(expected)]);
  return a.reduce((diff, value, i) => diff | (value ^ b[i]), 0) === 0;
}

export async function handler(request: Request): Promise<Response> {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const token = request.headers.get("x-mefrion-worker");
  if (!token || token.length < 32 || token.length > 256) return reply(401, { error: "authentication_required" });
  const server = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
  const auth = await server.rpc("mefrion_cloud_worker_authorize", { p_token: token });
  if (auth.error || auth.data !== true) return reply(401, { error: "authentication_required" });
  if (Number(request.headers.get("content-length")) > 2048) return reply(413, { error: "request_too_large" });
  let input: { job_id: string; lease: string };
  try {
    const text = await request.text();
    if (text.length > 2048) return reply(413, { error: "request_too_large" });
    input = JSON.parse(text);
    if (!uuid.test(input.job_id) || !uuid.test(input.lease)) throw Error();
  } catch { return reply(400, { error: "request_invalid" }); }
  const rpc = async (name: string, params: object) => {
    const result = await server.rpc(name, params);
    if (result.error) throw new MediaError("database_unavailable");
    return result.data;
  };
  const complete = (success: boolean, error: string | null = null, cursor: number | null = null) => rpc("mefrion_cloud_work_complete", { p_id: input.job_id, p_lease: input.lease, p_success: success, p_error: error, p_cursor: cursor });
  const download = async (path: string, limit: number) => {
    if (!safeObjectPath(path)) throw new MediaError("source_path_invalid");
    const result = await server.storage.from("family-originals").download(path);
    if (result.error || !result.data) throw new MediaError("source_unavailable");
    if (result.data.size > limit) throw new MediaError("source_size");
    return new Uint8Array(await result.data.arrayBuffer());
  };
  const upload = async (path: string, data: Uint8Array, contentType: string) => {
    if (!safeObjectPath(path)) throw new MediaError("destination_path_invalid");
    const result = await server.storage.from("public-derived").upload(path, data, { contentType, upsert: true, cacheControl: "0" });
    if (result.error) throw new MediaError("upload_failed");
  };
  const removeAndVerify = async (bucket: string, path: string) => {
    if (!["family-originals", "public-derived"].includes(bucket) || !safeObjectPath(path)) throw new MediaError("deletion_path_invalid");
    const removed = await server.storage.from(bucket).remove([path]);
    if (removed.error) throw new MediaError("deletion_failed");
    const slash = path.lastIndexOf("/"), name = path.slice(slash + 1), parent = slash < 0 ? "" : path.slice(0, slash);
    const listed = await server.storage.from(bucket).list(parent, { search: name, limit: 100 });
    if (listed.error || listed.data?.some(item => item.name === name)) throw new MediaError("deletion_unverified");
  };
  try {
    const job: Job | null = await rpc("mefrion_cloud_work_get", { p_id: input.job_id, p_lease: input.lease });
    if (!job) return reply(200, { skipped: true });
    if (job.kind === "image") {
      await upload(job.path, await imageDerivative(await download(String(job.payload.source_path), 20 * 1024 * 1024)), "image/jpeg");
    } else if (job.kind === "video") {
      const source = String(job.payload.source_path);
      if (!source.endsWith(".mp4") || !job.path.endsWith(".mp4")) throw new MediaError("video_path_invalid");
      await upload(job.path, videoDerivative(await download(source, 50 * 1024 * 1024)), "video/mp4");
    } else if (job.kind === "delete") {
      await removeAndVerify(String(job.payload.bucket ?? "family-originals"), job.path);
      if (!await rpc("mefrion_deletion_ack", { p_id: job.entity_id, p_path: job.path })) throw new MediaError("deletion_ack_failed");
    } else if (job.kind === "retirement") {
      const originals = job.payload.paths as { bucket: string; path: string }[];
      if (!Array.isArray(originals)) throw new MediaError("retirement_paths_invalid");
      const seen = new Set<string>();
      const paths = originals.flatMap(item => item.path.endsWith(".mp4") ? [item, { bucket: item.bucket, path: item.path.slice(0, -4) + (item.bucket === "family-originals" ? "-preview.jpg" : ".jpg") }] : [item]).filter(item => {
        const key = item.bucket + "/" + item.path; if (seen.has(key)) return false; seen.add(key); return true;
      });
      const cursor = Number(job.payload.cursor ?? 0), end = Math.min(cursor + 10, paths.length);
      for (let i = cursor; i < end; i++) await removeAndVerify(paths[i].bucket, paths[i].path);
      if (end < paths.length) {
        await complete(true, null, end);
        return reply(200, { continued: true });
      }
      const existing = await server.auth.admin.getUserById(job.entity_id);
      if (existing.error || !existing.data.user) throw new MediaError("retirement_identity_unavailable");
      if (!(existing.data.user as unknown as { deleted_at?: string }).deleted_at) {
        const erased = await server.auth.admin.deleteUser(job.entity_id, true);
        if (erased.error) throw new MediaError("retirement_auth_failed");
      }
      const verified = await server.auth.admin.getUserById(job.entity_id);
      if (verified.error || !(verified.data.user as unknown as { deleted_at?: string } | null)?.deleted_at) throw new MediaError("retirement_auth_unverified");
      if (!await rpc("mefrion_retirement_ack", { p_user: job.entity_id })) throw new MediaError("retirement_ack_failed");
    } else throw new MediaError("job_kind_invalid");
    if (!await complete(true)) throw new MediaError("completion_unconfirmed");
    return reply(200, { processed: true });
  } catch (error) {
    const code = error instanceof MediaError ? error.code : "processing_failed";
    // No names, photo paths, request bodies, tokens or exception text in logs.
    try { await complete(false, code); } catch { /* lease expiry provides retry */ }
    return reply(503, { error: code });
  }
}

Deno.serve(handler);
