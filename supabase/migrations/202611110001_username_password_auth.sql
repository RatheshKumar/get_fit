-- Review this migration before applying it to the linked Supabase project.
alter table public.profiles
  add column if not exists username text,
  add column if not exists phone text,
  add column if not exists status text not null default 'active'
    check (status in ('active', 'paused'));

create unique index if not exists profiles_username_unique
  on public.profiles (lower(username)) where username is not null;
create unique index if not exists profiles_phone_unique on public.profiles (phone) where phone is not null;
alter table public.clients drop constraint if exists clients_contact_check;

-- Preserve existing account metadata when populating the new login handle.
update public.profiles p
set username = lower(split_part(u.email, '@', 1))
from auth.users u
where u.id = p.id and p.username is null and u.email like '%@example.com';

create table if not exists public.client_details (
  client_id uuid primary key references public.clients(id) on delete cascade,
  goal text not null default '',
  height_cm numeric(6,2) check (height_cm between 30 and 300),
  start_weight_kg numeric(6,2) check (start_weight_kg between 1 and 1000),
  notes_private text not null default '',
  fee_amount numeric(12,2) check (fee_amount >= 0),
  fee_due_date date,
  fee_status text not null default 'unpaid' check (fee_status in ('paid','unpaid','overdue')),
  updated_at timestamptz not null default now()
);

create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  muscle_group text not null default '', media_url text, instructions text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  type text not null check (type in ('workout','diet')),
  is_template boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.plan_items (
  id uuid primary key default gen_random_uuid(), plan_id uuid not null references public.plans(id) on delete cascade,
  exercise_id uuid references public.exercises(id) on delete set null,
  day text not null default '', sets integer check (sets between 1 and 100), reps text not null default '',
  rest integer not null default 60 check (rest between 0 and 7200), notes text not null default '',
  position integer not null default 1
);

create table if not exists public.client_plans (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  plan_id uuid not null references public.plans(id) on delete cascade,
  start_date date not null default current_date, end_date date,
  check (end_date is null or end_date >= start_date)
);

create table if not exists public.workout_logs (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  log_date date not null default current_date, exercise text not null, completed boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.set_logs (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  workout_log_id uuid references public.workout_logs(id) on delete cascade,
  log_date date not null default current_date, exercise text not null, set_number integer not null check (set_number > 0),
  reps integer not null check (reps >= 0), weight numeric(8,2) not null default 0 check (weight >= 0),
  completed boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.meal_logs (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  log_date date not null default current_date, meal text not null, notes text not null default '', created_at timestamptz not null default now()
);
create table if not exists public.water_logs (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  log_date date not null default current_date, amount_ml integer not null check (amount_ml > 0), created_at timestamptz not null default now()
);
create table if not exists public.body_metrics (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  log_date date not null default current_date, weight numeric(7,2), measurements jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists public.progress_photos (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete cascade,
  storage_path text not null, log_date date not null default current_date, created_at timestamptz not null default now()
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(), sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '', media_url text, type text not null default 'text',
  created_at timestamptz not null default now(), read_at timestamptz,
  check (sender_id <> receiver_id)
);
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(), trainer_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  start_time timestamptz not null, notes text not null default ''
);
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(), trainer_id uuid not null references public.profiles(id) on delete cascade,
  body text not null, target jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique, platform text not null check (platform in ('android','ios')),
  updated_at timestamptz not null default now()
);
create table if not exists public.trainer_signup_limits (
  fingerprint text primary key,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0
);
alter table public.trainer_signup_limits enable row level security;
revoke all on public.trainer_signup_limits from anon,authenticated;
grant all on public.trainer_signup_limits to service_role;

create or replace function public.consume_trainer_signup_limit(input_fingerprint text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare allowed boolean;
begin
  insert into public.trainer_signup_limits(fingerprint,window_started_at,attempts)
  values(input_fingerprint,now(),1)
  on conflict(fingerprint) do update set
    attempts=case when public.trainer_signup_limits.window_started_at < now()-interval '1 hour' then 1 else public.trainer_signup_limits.attempts+1 end,
    window_started_at=case when public.trainer_signup_limits.window_started_at < now()-interval '1 hour' then now() else public.trainer_signup_limits.window_started_at end;
  select attempts <= 5 into allowed from public.trainer_signup_limits where trainer_signup_limits.fingerprint=input_fingerprint;
  return allowed;
end;
$$;
revoke all on function public.consume_trainer_signup_limit(text) from public;
grant execute on function public.consume_trainer_signup_limit(text) to service_role;

create index if not exists plans_trainer_idx on public.plans(trainer_id);
create index if not exists client_plans_client_idx on public.client_plans(client_id,start_date desc);
create index if not exists set_logs_client_date_idx on public.set_logs(client_id,log_date desc);
create index if not exists messages_pair_created_idx on public.messages(sender_id,receiver_id,created_at desc);

do $$ declare t text; begin
  foreach t in array array['client_details','exercises','plans','plan_items','client_plans','workout_logs','set_logs','meal_logs','water_logs','body_metrics','progress_photos','messages','sessions','announcements','device_tokens'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Access rules use the trainer-owned client row as the authority for all client data.
create or replace function public.owns_client(target_client_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.clients c where c.id=target_client_id and
    (c.profile_id=(select auth.uid()) or c.trainer_id=(select auth.uid())))
$$;
revoke all on function public.owns_client(uuid) from public;
grant execute on function public.owns_client(uuid) to authenticated;

create policy client_details_owner on public.client_details for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy exercises_owner on public.exercises for all to authenticated
  using (trainer_id=(select auth.uid())) with check (trainer_id=(select auth.uid()));
create policy exercises_read_assigned on public.exercises for select to authenticated using (
  exists(select 1 from public.plan_items pi join public.plans p on p.id=pi.plan_id
    join public.client_plans cp on cp.plan_id=p.id join public.clients c on c.id=cp.client_id
    where pi.exercise_id=exercises.id and c.profile_id=(select auth.uid()) and p.trainer_id=c.trainer_id));
create policy plans_owner on public.plans for all to authenticated
  using (trainer_id=(select auth.uid())) with check (trainer_id=(select auth.uid()));
create policy plans_read_assigned on public.plans for select to authenticated using (
  exists(select 1 from public.client_plans cp join public.clients c on c.id=cp.client_id
    where cp.plan_id=plans.id and c.profile_id=(select auth.uid()) and c.trainer_id=plans.trainer_id));
create policy plan_items_owner on public.plan_items for all to authenticated
  using (exists(select 1 from public.plans p where p.id=plan_id and p.trainer_id=(select auth.uid())))
  with check (exists(select 1 from public.plans p where p.id=plan_id and p.trainer_id=(select auth.uid())));
create policy plan_items_read_assigned on public.plan_items for select to authenticated using (
  exists(select 1 from public.plans p join public.client_plans cp on cp.plan_id=p.id
    join public.clients c on c.id=cp.client_id where p.id=plan_items.plan_id
      and c.profile_id=(select auth.uid()) and c.trainer_id=p.trainer_id));
create policy client_plans_read_assigned on public.client_plans for select to authenticated
  using (public.owns_client(client_id) and exists(
    select 1 from public.plans p join public.clients c on c.id=client_plans.client_id
    where p.id=client_plans.plan_id and p.trainer_id=c.trainer_id));
create policy client_plans_trainer_manage on public.client_plans for all to authenticated
  using (exists(select 1 from public.plans p where p.id=plan_id and p.trainer_id=(select auth.uid()))
    and exists(select 1 from public.clients c where c.id=client_id and c.trainer_id=(select auth.uid())))
  with check (exists(select 1 from public.plans p where p.id=plan_id and p.trainer_id=(select auth.uid()))
    and exists(select 1 from public.clients c where c.id=client_id and c.trainer_id=(select auth.uid())));
create policy workout_logs_owner on public.workout_logs for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy set_logs_owner on public.set_logs for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy meal_logs_owner on public.meal_logs for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy water_logs_owner on public.water_logs for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy body_metrics_owner on public.body_metrics for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy progress_photos_owner on public.progress_photos for all to authenticated
  using (public.owns_client(client_id)) with check (public.owns_client(client_id));
create policy sessions_owner on public.sessions for all to authenticated
  using (trainer_id=(select auth.uid()) or public.owns_client(client_id))
  with check (trainer_id=(select auth.uid()) and public.owns_client(client_id));
create policy announcements_trainer on public.announcements for all to authenticated
  using (trainer_id=(select auth.uid())) with check (trainer_id=(select auth.uid()));
create policy announcements_client_read on public.announcements for select to authenticated
  using (exists(select 1 from public.clients c where c.profile_id=(select auth.uid())
    and c.trainer_id=announcements.trainer_id
    and ((announcements.target->>'all')='true' or announcements.target @> jsonb_build_object('client_ids',jsonb_build_array(c.id::text)))));
create policy device_tokens_owner on public.device_tokens for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy messages_participant on public.messages for select to authenticated
  using (sender_id=(select auth.uid()) or receiver_id=(select auth.uid()));
create or replace function public.client_can_access_message_peer(peer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.clients c where
    (c.profile_id=(select auth.uid()) and c.trainer_id=peer) or
    (c.profile_id=peer and c.trainer_id=(select auth.uid())))
$$;
revoke all on function public.client_can_access_message_peer(uuid) from public;
grant execute on function public.client_can_access_message_peer(uuid) to authenticated;
drop policy if exists messages_participant on public.messages;
create policy messages_participant on public.messages for select to authenticated
  using ((sender_id=(select auth.uid()) or receiver_id=(select auth.uid())) and
    public.client_can_access_message_peer(case when sender_id=(select auth.uid()) then receiver_id else sender_id end))
;
create policy messages_sender_insert on public.messages for insert to authenticated
  with check (sender_id=(select auth.uid()) and public.client_can_access_message_peer(receiver_id));
create policy messages_receiver_read_update on public.messages for update to authenticated
  using (receiver_id=(select auth.uid()) and public.client_can_access_message_peer(sender_id))
  with check (receiver_id=(select auth.uid()) and public.client_can_access_message_peer(sender_id));

create policy profiles_self_or_trainer_select on public.profiles for select to authenticated
  using (id=(select auth.uid()) or trainer_id=(select auth.uid()));
create policy profiles_trainer_insert_self on public.profiles for insert to authenticated
  with check (id=(select auth.uid()) and role='trainer' and trainer_id is null);

insert into storage.buckets(id,name,public) values
  ('progress-photos','progress-photos',false),('chat-media','chat-media',false),('exercise-media','exercise-media',false)
on conflict (id) do nothing;
create policy progress_photos_owner on storage.objects for all to authenticated
  using (bucket_id='progress-photos' and public.owns_client((storage.foldername(name))[1]::uuid))
  with check (bucket_id='progress-photos' and public.owns_client((storage.foldername(name))[1]::uuid));
create policy exercise_media_trainer on storage.objects for all to authenticated
  using (bucket_id='exercise-media' and (storage.foldername(name))[1]=(select auth.uid())::text)
  with check (bucket_id='exercise-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy chat_media_participant on storage.objects for all to authenticated
  using (bucket_id='chat-media' and public.client_can_access_message_peer((storage.foldername(name))[1]::uuid))
  with check (bucket_id='chat-media' and (storage.foldername(name))[2]=(select auth.uid())::text
    and public.client_can_access_message_peer((storage.foldername(name))[1]::uuid));

alter publication supabase_realtime add table public.messages, public.set_logs, public.workout_logs, public.client_plans, public.announcements;

grant select,insert,update,delete on public.exercises,public.plans,public.plan_items,public.client_plans,public.workout_logs,public.set_logs,public.meal_logs,public.water_logs,public.body_metrics,public.progress_photos,public.messages,public.sessions,public.announcements,public.device_tokens to authenticated;
revoke all on public.client_details from anon,authenticated;
grant select (client_id,goal,height_cm,start_weight_kg,fee_amount,fee_due_date,fee_status,updated_at) on public.client_details to authenticated;
grant insert (client_id,goal,height_cm,start_weight_kg,fee_amount,fee_due_date,fee_status) on public.client_details to authenticated;
grant update (goal,height_cm,start_weight_kg,fee_amount,fee_due_date,fee_status) on public.client_details to authenticated;
revoke update on public.messages from authenticated;
grant update (read_at) on public.messages to authenticated;
grant all on public.client_details,public.exercises,public.plans,public.plan_items,public.client_plans,public.workout_logs,public.set_logs,public.meal_logs,public.water_logs,public.body_metrics,public.progress_photos,public.messages,public.sessions,public.announcements,public.device_tokens to service_role;

-- Isolation checks: substitute real profile/client UUIDs from a non-production test project.
-- Run as CLIENT_A; the final query must return zero rows for CLIENT_B's records.
-- set role authenticated;
-- set request.jwt.claim.sub = 'CLIENT_A_PROFILE_UUID';
-- select * from public.workout_logs where client_id = 'CLIENT_B_CLIENT_UUID';
-- select * from public.set_logs where client_id = 'CLIENT_B_CLIENT_UUID';
-- reset role;
