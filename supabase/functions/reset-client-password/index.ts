import { createClient } from 'npm:@supabase/supabase-js@2';

const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
const randomPassword = () => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (byte) => chars[byte % chars.length]).join('');
};
Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return reply({ error: 'Method not allowed.' }, 405);
  const url = Deno.env.get('SUPABASE_URL'), anon = Deno.env.get('SUPABASE_ANON_KEY'), service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!url || !anon || !service || !authorization) return reply({ error: 'Password reset service is not configured.' }, 500);
  const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return reply({ error: 'Sign in as a trainer first.' }, 401);
  let input: { client_id?: unknown };
  try { input = await request.json(); } catch { return reply({ error: 'Request must contain valid JSON.' }, 400); }
  if (typeof input.client_id !== 'string') return reply({ error: 'Client ID is required.' }, 400);
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: trainer } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (trainer?.role !== 'trainer') return reply({ error: 'Only trainers can reset client passwords.' }, 403);
  const { data: client } = await admin.from('clients').select('profile_id').eq('id', input.client_id).eq('trainer_id', user.id).maybeSingle();
  if (!client?.profile_id) return reply({ error: 'Client account not found.' }, 404);
  const password = randomPassword();
  const { error } = await admin.auth.admin.updateUserById(client.profile_id, { password });
  if (error) return reply({ error: 'Could not reset the client password.' }, 500);
  return reply({ password });
});
