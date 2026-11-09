create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('trainer', 'client')),
  trainer_id uuid references public.profiles (id) on delete restrict,
  full_name text not null check (char_length(trim(full_name)) between 1 and 120),
  created_at timestamptz not null default now(),
  constraint profiles_trainer_role_check check (
    (role = 'trainer' and trainer_id is null)
    or (role = 'client' and trainer_id is not null and trainer_id <> id)
  )
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles (id) on delete cascade,
  profile_id uuid unique references public.profiles (id) on delete set null,
  full_name text not null check (char_length(trim(full_name)) between 1 and 120),
  email text,
  phone text,
  goal text not null check (char_length(trim(goal)) between 1 and 500),
  status text not null default 'active' check (status in ('active', 'paused')),
  starting_weight_kg numeric(6, 2) check (starting_weight_kg > 0),
  current_weight_kg numeric(6, 2) check (current_weight_kg > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_contact_check check (email is not null or phone is not null)
);

create table public.client_private_notes (
  client_id uuid primary key references public.clients (id) on delete cascade,
  trainer_id uuid not null references public.profiles (id) on delete cascade,
  notes text not null default '',
  updated_at timestamptz not null default now()
);

create index clients_trainer_status_idx on public.clients (trainer_id, status);
create index profiles_trainer_id_idx on public.profiles (trainer_id);

create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger clients_touch_updated_at
before update on public.clients
for each row execute function public.touch_updated_at();

create trigger client_private_notes_touch_updated_at
before update on public.client_private_notes
for each row execute function public.touch_updated_at();

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.client_private_notes enable row level security;

create policy profiles_read_self_or_trainer
on public.profiles for select to authenticated
using (id = (select auth.uid()) or trainer_id = (select auth.uid()));

create policy profiles_create_trainer
on public.profiles for insert to authenticated
with check (
  id = (select auth.uid())
  and role = 'trainer'
  and trainer_id is null
);

create policy profiles_update_trainer_name
on public.profiles for update to authenticated
using (id = (select auth.uid()) and role = 'trainer')
with check (id = (select auth.uid()) and role = 'trainer' and trainer_id is null);

create policy clients_read_owned
on public.clients for select to authenticated
using (
  trainer_id = (select auth.uid())
  or profile_id = (select auth.uid())
);

create policy clients_create_for_self
on public.clients for insert to authenticated
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'trainer'
  )
  and profile_id is null
);

create policy clients_update_owned
on public.clients for update to authenticated
using (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'trainer'
  )
)
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'trainer'
  )
);

create policy clients_delete_owned
on public.clients for delete to authenticated
using (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'trainer'
  )
);

create policy client_private_notes_trainer_access
on public.client_private_notes for all to authenticated
using (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.clients
    where id = client_id and trainer_id = (select auth.uid())
  )
)
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.clients
    where id = client_id and trainer_id = (select auth.uid())
  )
);

alter publication supabase_realtime add table public.clients;

grant select, delete on public.clients to authenticated;
grant insert (trainer_id, full_name, email, phone, goal, starting_weight_kg, current_weight_kg)
  on public.clients to authenticated;
grant update (full_name, email, phone, goal, status, starting_weight_kg, current_weight_kg)
  on public.clients to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.client_private_notes to authenticated;
grant all on public.profiles, public.clients, public.client_private_notes to service_role;

comment on table public.profiles is 'Authenticated account role and trainer relationship.';
comment on table public.clients is 'Trainer-owned client records; profile linkage is service-managed.';
comment on table public.client_private_notes is 'Trainer-only private notes, isolated from client-visible records.';