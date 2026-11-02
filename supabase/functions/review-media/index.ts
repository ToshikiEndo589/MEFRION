import { serveMonitored } from '../_shared/security_monitor.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const baseHeaders = {
  'Cache-Control': 'private, no-store, max-age=0',
  'Pragma': 'no-cache',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
};
const failure = (status: number, headers: Record<string, string>) =>
  new Response(JSON.stringify({ error: status === 401 ? 'authentication_required' : 'not_found' }), {
    status, headers: { ...baseHeaders, ...headers, 'Content-Type': 'application/json' },
  });

export async function handler(request: Request): Promise<Response> {
  const origin = request.headers.get('Origin');
  const allowed = origin === 'https://mefrion.vercel.app';
  const cors: Record<string, string> = allowed ? {
    'Access-Control-Allow-Origin': origin!,
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey',
    'Vary': 'Origin',
  } : {};
  if (request.method === 'OPTIONS') return new Response(null, { status: allowed ? 204 : 403, headers: { ...baseHeaders, ...cors } });
  if (request.method !== 'GET') return new Response(null, { status: 405, headers: baseHeaders });
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) return failure(401, cors);
  const id = new URL(request.url).searchParams.get('media');
  if (!id || !uuid.test(id)) return failure(404, cors);

  const url = Deno.env.get('SUPABASE_URL')!;
  const user = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: authError } = await user.auth.getUser(auth.slice(7));
  if (authError || !identity.user || identity.user.is_anonymous) return failure(401, cors);
  const { data: record, error } = await user.rpc('mefrion_content_review_media', { p_media: id });
  if (error || !record?.path || !['image', 'video'].includes(record.kind)) return failure(404, cors);
  const server = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: blob, error: downloadError } = await server.storage.from('public-derived').download(record.path);
  if (downloadError || !blob) return failure(404, cors);
  const { data: recheck, error: revoked } = await user.rpc('mefrion_content_review_media', { p_media: id });
  if (revoked || recheck?.path !== record.path || recheck?.post_id !== record.post_id) return failure(404, cors);
  return new Response(blob, {
    status: 200,
    headers: { ...baseHeaders, ...cors, 'Content-Type': record.kind === 'video' ? 'video/mp4' : 'image/jpeg' },
  });
}

serveMonitored('review-media', handler);
