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
    return response({ error: 'The account service is not configured.' }, 500);
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return response({ error: 'Sign in to remove a client.' }, 401);

  let input: { client_id?: unknown };
  try {
    input = await request.json();
  } catch {
    return response({ error: 'Request must contain valid JSON.' }, 400);
  }
  if (typeof input.client_id !== 'string') return response({ error: 'Client ID is required.' }, 400);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: client, error: clientError } = await admin
    .from('clients')
    .select('id, profile_id')
    .eq('id', input.client_id)
    .eq('trainer_id', user.id)
    .maybeSingle();
  if (clientError || !client) return response({ error: 'Client not found.' }, 404);

  if (client.profile_id) {
    const { error } = await admin.auth.admin.deleteUser(client.profile_id);
    if (error) return response({ error: 'Could not delete the client account.' }, 500);
  }
  const { error: deleteError } = await admin
    .from('clients')
    .delete()
    .eq('id', client.id)
    .eq('trainer_id', user.id);
  if (deleteError) return response({ error: 'Could not remove the client record.' }, 500);
  return response({ deleted: true });
});