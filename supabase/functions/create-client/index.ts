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
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!url || !anon || !service || !authorization) return reply({ error: 'Client service is not configured.' }, 500);
  const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return reply({ error: 'Sign in as a trainer first.' }, 401);
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: trainer } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (trainer?.role !== 'trainer') return reply({ error: 'Only trainers can create clients.' }, 403);
  let input: Record<string, unknown>;
  try { input = await request.json(); } catch { return reply({ error: 'Request must contain valid JSON.' }, 400); }

  const name = typeof input.full_name === 'string' ? input.full_name.trim() : '';
  const goal = typeof input.goal === 'string' ? input.goal.trim() : '';
  const loginId = typeof input.login_id === 'string' ? input.login_id.trim() : '';
  const emailInput = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const isEmailId = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(loginId);
  const digits = loginId.replace(/\D/g, '');
  const isPhoneId = !isEmailId && digits.length >= 8 && digits.length <= 15;
  const username = !isEmailId && !isPhoneId ? loginId.toLowerCase() : null;
  const email = isEmailId ? loginId.toLowerCase() : emailInput || null;
  const phone = isPhoneId ? `+${digits}` : null;
  const weight = input.starting_weight_kg == null ? null : Number(input.starting_weight_kg);
  if (!name || name.length > 120 || !goal || goal.length > 500 || !loginId ||
      (!isEmailId && !isPhoneId && !/^[a-z0-9_.]{3,40}$/.test(username ?? '')) ||
      (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) ||
      (weight != null && (!Number.isFinite(weight) || weight <= 0 || weight > 999.99))) {
    return reply({ error: 'Enter a valid name, goal, email/username/phone, and weight.' }, 400);
  }
  if (username) {
    const { data: existing } = await admin.from('profiles').select('id').eq('username', username).maybeSingle();
    if (existing) return reply({ error: 'That username is already in use.' }, 409);
  }
  const authEmail = isEmailId ? loginId.toLowerCase() : `${isPhoneId ? digits : username}@example.com`;
  const password = randomPassword();
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: authEmail, password, email_confirm: true,
    user_metadata: { full_name: name, username, invited_by: user.id },
  });
  if (createError || !created.user) return reply({ error: createError?.message ?? 'Could not create client account.' }, 400);
  const clientUserId = created.user.id;
  const { error: profileError } = await admin.from('profiles').insert({
    id: clientUserId, role: 'client', trainer_id: user.id, full_name: name,
    username, phone,
  });
  if (profileError) {
    await admin.auth.admin.deleteUser(clientUserId);
    return reply({ error: `Could not create client profile: ${profileError.message}` }, 500);
  }
  const { data: client, error: clientError } = await admin.from('clients').insert({
    trainer_id: user.id, profile_id: clientUserId, full_name: name,
    email, phone, goal, starting_weight_kg: weight, current_weight_kg: weight,
  }).select('id').single();
  if (clientError) {
    await admin.auth.admin.deleteUser(clientUserId);
    return reply({ error: 'Could not save client details.' }, 500);
  }
  const { error: detailsError } = await admin.from('client_details').insert({
    client_id: client.id,
    goal,
    start_weight_kg: weight,
  });
  if (detailsError) {
    await admin.from('clients').delete().eq('id', client.id);
    await admin.auth.admin.deleteUser(clientUserId);
    return reply({ error: 'Could not save the extended client details.' }, 500);
  }
  return reply({ client_id: client.id, login_id: loginId, password });
});
