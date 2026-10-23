import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const reply = (status: number, body: object) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async request => {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const token = request.headers.get("x-mefrion-worker");
  if (!token || token.length < 32 || token.length > 256) return reply(401, { error: "authentication_required" });
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const auth = await client.rpc("mefrion_cloud_worker_authorize", { p_token: token });
  if (auth.error || auth.data !== true) return reply(401, { error: "authentication_required" });
  try {
    const snapshot = await client.rpc("mefrion_cloud_database_snapshot");
    if (snapshot.error || !snapshot.data?.encrypted_base64) throw Error();
    const bytes = Uint8Array.from(atob(snapshot.data.encrypted_base64.replace(/\s/g, "")), c => c.charCodeAt(0));
    const name = new Date().toISOString().replaceAll(":", "-") + ".pgp";
    const stored = await client.storage.from("system-backups").upload(name, bytes, { contentType: "application/octet-stream", upsert: false, cacheControl: "0" });
    if (stored.error) throw Error();
    const downloaded = await client.storage.from("system-backups").download(name);
    if (downloaded.error || !downloaded.data) throw Error();
    const digest = async (data: Uint8Array) => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", data))).join(",");
    if (await digest(bytes) !== await digest(new Uint8Array(await downloaded.data.arrayBuffer()))) throw Error();
    const listed = await client.storage.from("system-backups").list("", { limit: 1000 });
    if (listed.error) throw Error();
    const expired = listed.data.filter(file => /^20[0-9-]+T[0-9.-]+Z\.pgp$/.test(file.name) && Date.parse(file.created_at) < Date.now() - 7 * 86400000).map(file => file.name);
    if (expired.length && (await client.storage.from("system-backups").remove(expired)).error) throw Error();
    await client.rpc("mefrion_cloud_backup_finish", { p_success: true, p_bytes: bytes.length });
    return reply(200, { stored: true, encrypted: true, bytes: bytes.length, retention_days: 7, includes_media_bytes: false });
  } catch {
    await client.rpc("mefrion_cloud_backup_finish", { p_success: false });
    return reply(503, { error: "snapshot_failed" });
  }
});
