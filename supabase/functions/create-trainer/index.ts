import { createClient } from 'npm:@supabase/supabase-js@2';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...headers, 'Content-Type': 'application/json' },
});

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return reply({ error: 'Method not allowed.' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return reply({ error: 'Account service is not configured.' }, 500);

  let input: Record<string, unknown>;
  try { input = await request.json(); } catch { return reply({ error: 'Request must contain valid JSON.' }, 400); }
  const loginId = typeof input.login_id === 'string' ? input.login_id.trim() : '';
  const name = typeof input.full_name === 'string' ? input.full_name.trim() : '';
  const password = typeof input.password === 'string' ? input.password : '';
  const isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(loginId);
  const digits = loginId.replace(/[^0-9]/g, '');
  const isPhone = !isEmail && digits.length >= 8 && digits.length <= 15;
  const username = !isEmail && !isPhone ? loginId.toLowerCase() : null;
  if ((!isEmail && !isPhone && !/^[a-z0-9_.]{3,40}$/.test(username ?? '')) ||
      !name || name.length > 120 || password.length < 8 || password.length > 72) {
    return reply({ error: 'Enter a valid email, username, or phone, name, and password of 8–72 characters.' }, 400);
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const forwardedFor = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
  const material = `${forwardedFor}:${request.headers.get('user-agent') ?? 'unknown'}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(material));
  const fingerprint = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  const { data: allowed, error: limitError } = await admin.rpc('consume_trainer_signup_limit', { input_fingerprint: fingerprint });
  if (limitError) return reply({ error: 'Signup security check is unavailable. Apply the reviewed auth migration.' }, 500);
  if (!allowed) return reply({ error: 'Too many account registrations from this connection. Try again later.' }, 429);
  const syntheticEmail = isEmail ? loginId.toLowerCase() : `${isPhone ? digits : username}@example.com`;
  const duplicate = await admin.from('profiles').select('id').eq('username', username ?? '').maybeSingle();
  if (username && duplicate.data) return reply({ error: 'That username is already in use.' }, 409);
  const { data, error } = await admin.auth.admin.createUser({
    email: syntheticEmail,
    password,
    email_confirm: true,
    user_metadata: { full_name: name, username },
  });
  if (error || !data.user) return reply({ error: error?.message ?? 'Could not create account.' }, 400);

  const { error: profileError } = await admin.from('profiles').insert({
    id: data.user.id,
    role: 'trainer',
    full_name: name,
    username,
    phone: isPhone ? `+${digits}` : null,
    status: 'active',
  });
  if (profileError) {
    await admin.auth.admin.deleteUser(data.user.id);
    return reply({ error: 'Could not create trainer profile. Apply the reviewed auth migration first.' }, 500);
  }
  return reply({ created: true });
});
