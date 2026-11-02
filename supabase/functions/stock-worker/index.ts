import { serveMonitored } from '../_shared/security_monitor.ts';
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { jpegDimensions } from "../_shared/media.ts";

const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const reply = (status: number, value: object) => new Response(JSON.stringify(value), { status, headers });
import { safeTask, type Task } from "./validation.ts";
export async function handler(request: Request): Promise<Response> {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const token = request.headers.get("x-mefrion-worker");
  if (!token || token.length < 32 || token.length > 256) return reply(401, { error: "authentication_required" });
  const server = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
  const auth = await server.rpc("mefrion_cloud_worker_authorize", { p_token: token });
  if (auth.error || auth.data !== true) return reply(401, { error: "authentication_required" });
  const batch = await server.rpc("mefrion_stock_batch");
  if (batch.error || !Array.isArray(batch.data)) return reply(503, { error: "stock_batch_failed" });
  const tasks = batch.data as Task[];
  let published = 0, failed = 0, cancelled = 0;
  for (let start = 0; start < tasks.length; start += 4) {
    await Promise.all(tasks.slice(start, start + 4).map(async task => {
      try {
        if (!safeTask(task)) throw Error("stock_path_invalid");
        // These are already decoded, species-filtered, licensed catalogue JPEGs.
        // Never fetch a caller-provided URL or access customer originals.
        const file = await server.storage.from("reference-thumbnails").download(task.reference_path);
        if (file.error || !file.data || file.data.size < 100 || file.data.size > 200000 || file.data.type !== "image/jpeg") throw Error("stock_source_invalid");
        const bytes = new Uint8Array(await file.data.arrayBuffer());
        jpegDimensions(bytes);
        const copies = await Promise.all([
          server.storage.from("family-originals").upload(task.original_path, bytes, { contentType: "image/jpeg", upsert: true, cacheControl: "0" }),
          server.storage.from("public-derived").upload(task.public_path, bytes, { contentType: "image/jpeg", upsert: true, cacheControl: "0" }),
        ]);
        if (copies.some(c => c.error)) throw Error("stock_copy_failed");
        const done = await server.rpc("mefrion_stock_complete", { p_task: task.id, p_lease: task.lease, p_success: true });
        if (done.error) throw Error("stock_complete_failed");
        if (done.data === true) published++;
        else {
          cancelled++;
          // SQL queues cleanup only for an actually cancelled reservation.
          // A stale lease must not erase a newer worker's successful copy.
        }
      } catch (error) {
        failed++;
        const code = error instanceof Error && /^stock_[a-z_]+$/.test(error.message) ? error.message : "stock_processing_failed";
        await server.rpc("mefrion_stock_complete", { p_task: task.id, p_lease: task.lease, p_success: false, p_error: code });
      }
    }));
  }
  return reply(failed ? 503 : 200, { processed: tasks.length, published, cancelled, failed });
}
serveMonitored('stock-worker', handler);
