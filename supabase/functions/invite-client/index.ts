import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response({ error: 'Method not allowed.' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!url || !anonKey || !serviceKey || !authorization) {
    return response({ error: 'The invitation service is not configured.' }, 500);
  }

  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user) return response({ error: 'Sign in to invite a client.' }, 401);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: trainer, error: trainerError } = await admin
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();
  if (trainerError || trainer?.role !== 'trainer') {
    return response({ error: 'Only trainers can invite clients.' }, 403);
  }

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return response({ error: 'Request must contain valid JSON.' }, 400);
  }

  const fullName = typeof input.full_name === 'string' ? input.full_name.trim() : '';
  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const goal = typeof input.goal === 'string' ? input.goal.trim() : '';
  const phone = typeof input.phone === 'string' ? input.phone.trim() : null;
  const weight = input.starting_weight_kg == null ? null : Number(input.starting_weight_kg);
  if (!fullName || fullName.length > 120 || !goal || goal.length > 500 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      (weight !== null && (!Number.isFinite(weight) || weight <= 0 || weight > 999.99))) {
    return response({ error: 'Enter a name, valid email, goal, and positive starting weight.' }, 400);
  }

  const { data: invitation, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: Deno.env.get('CLIENT_APP_REDIRECT_URL'),
    data: { full_name: fullName, invited_by: user.id },
  });
  if (inviteError || !invitation.user) {
    return response({ error: inviteError?.message ?? 'Could not create the client invitation.' }, 400);
  }

  const clientUserId = invitation.user.id;
  const { error: profileError } = await admin.from('profiles').insert({
    id: clientUserId,
    role: 'client',
    trainer_id: user.id,
    full_name: fullName,
  });
  if (profileError) {
    await admin.auth.admin.deleteUser(clientUserId);
    return response({ error: 'Could not create the client profile.' }, 500);
  }

  const { data: client, error: clientError } = await admin.from('clients').insert({
    trainer_id: user.id,
    profile_id: clientUserId,
    full_name: fullName,
    email,
    phone,
    goal,
    starting_weight_kg: weight,
    current_weight_kg: weight,
  }).select('id').single();
  if (clientError) {
    await admin.auth.admin.deleteUser(clientUserId);
    return response({ error: 'Could not save the client record.' }, 500);
  }

  return response({ client_id: client.id });
});