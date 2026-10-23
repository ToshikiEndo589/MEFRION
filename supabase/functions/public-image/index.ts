import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const headers = { "Cache-Control": "private, no-store, max-age=0", "X-Content-Type-Options": "nosniff" };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async (request: Request) => {
  if (request.method !== "GET") return new Response(null, { status: 405, headers });
  const paramsIn = new URL(request.url).searchParams;
  const format = paramsIn.get("format");
  if (format !== null && format !== "video") return new Response(null, { status: 404, headers });
  const reference = paramsIn.get("reference");
  if (reference !== null) {
    if (!/^pexels-[0-9]+$/.test(reference) || paramsIn.has("media") || format !== null) return new Response(null, { status: 404, headers });
    const server = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const before = await server.rpc("mefrion_reference_image_path", { p_id: reference });
    if (before.error || typeof before.data !== "string") return new Response(null, { status: 404, headers });
    const file = await server.storage.from("reference-thumbnails").download(before.data);
    if (file.error || !file.data || file.data.size > 200000 || file.data.type !== "image/jpeg") return new Response(null, { status: 404, headers });
    const after = await server.rpc("mefrion_reference_image_path", { p_id: reference });
    if (after.error || after.data !== before.data) return new Response(null, { status: 404, headers });
    return new Response(file.data, { headers: { ...headers, "Content-Type": "image/jpeg" } });
  }
  const media = paramsIn.get("media");
  if (!media || !uuid.test(media)) return new Response(null, { status: 404, headers });
  const base = Deno.env.get("SUPABASE_URL")!;
  let actor: string | null = null;
  const bearer = request.headers.get("Authorization");
  if (bearer) {
    if (!bearer.startsWith("Bearer ")) return new Response(null, { status: 401, headers });
    const identity = createClient(base, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
    const { data, error } = await identity.auth.getUser(bearer.slice(7));
    if (error || !data.user) return new Response(null, { status: 401, headers });
    actor = data.user.id;
  }
  const server = createClient(base, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const params = { p_media: media, p_actor: actor };
  const procedure = format === "video" ? "mefrion_public_video_path" : "mefrion_public_image_path";
  const before = await server.rpc(procedure, params);
  if (before.error || typeof before.data !== "string") return new Response(null, { status: 404, headers });
  const file = await server.storage.from("public-derived").download(before.data);
  if (file.error || !file.data) return new Response(null, { status: 404, headers });
  if (format === "video" && (file.data.size > 52428800 || new TextDecoder().decode(await file.data.slice(4,8).arrayBuffer()) !== "ftyp")) return new Response(null, { status: 404, headers });
  const after = await server.rpc(procedure, params);
  if (after.error || after.data !== before.data) return new Response(null, { status: 404, headers });
  return new Response(file.data, { headers: { ...headers, "Content-Type": format === "video" ? "video/mp4" : "image/jpeg" } });
});
