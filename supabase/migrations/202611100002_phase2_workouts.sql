create table public.exercise_library (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  instructions text not null default '',
  media_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workout_plans (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workout_plan_exercises (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.workout_plans (id) on delete cascade,
  exercise_id uuid not null references public.exercise_library (id) on delete restrict,
  position integer not null check (position between 1 and 100),
  sets integer not null check (sets between 1 and 50),
  reps text not null check (char_length(trim(reps)) between 1 and 40),
  rest_seconds integer not null default 60 check (rest_seconds between 0 and 3600),
  notes text not null default '',
  created_at timestamptz not null default now(),
  unique (plan_id, position)
);

create table public.workout_assignments (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles (id) on delete cascade,
  client_id uuid not null references public.clients (id) on delete cascade,
  plan_id uuid not null references public.workout_plans (id) on delete restrict,
  starts_on date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index workout_assignments_client_active_idx
  on public.workout_assignments (client_id, is_active, starts_on desc);
create unique index workout_assignments_one_active_per_client_idx
  on public.workout_assignments (client_id) where is_active;
create index workout_plan_exercises_plan_position_idx
  on public.workout_plan_exercises (plan_id, position);

create function public.assign_workout_plan(target_client_id uuid, target_plan_id uuid)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  new_assignment_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to assign a workout plan';
  end if;

  update public.workout_assignments
  set is_active = false
  where client_id = target_client_id
    and trainer_id = auth.uid()
    and is_active;

  insert into public.workout_assignments (trainer_id, client_id, plan_id)
  values (auth.uid(), target_client_id, target_plan_id)
  returning id into new_assignment_id;

  return new_assignment_id;
end;
$$;

revoke all on function public.assign_workout_plan(uuid, uuid) from public;
grant execute on function public.assign_workout_plan(uuid, uuid) to authenticated;

create table public.workout_sessions (
  id uuid primary key,
  assignment_id uuid not null references public.workout_assignments (id) on delete cascade,
  client_id uuid not null references public.clients (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'completed')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint workout_sessions_completed_check check (
    (status = 'active' and completed_at is null)
    or (status = 'completed' and completed_at is not null)
  )
);

create index workout_sessions_client_started_idx
  on public.workout_sessions (client_id, started_at desc);

create table public.workout_set_logs (
  id uuid primary key,
  session_id uuid not null references public.workout_sessions (id) on delete cascade,
  plan_exercise_id uuid not null references public.workout_plan_exercises (id) on delete restrict,
  set_number integer not null check (set_number between 1 and 50),
  reps_completed integer not null check (reps_completed between 0 and 1000),
  weight_kg numeric(7, 2) not null check (weight_kg between 0 and 9999.99),
  logged_at timestamptz not null default now(),
  unique (session_id, plan_exercise_id, set_number)
);

create index workout_set_logs_session_idx on public.workout_set_logs (session_id, logged_at);

create trigger exercise_library_touch_updated_at
before update on public.exercise_library
for each row execute function public.touch_updated_at();

create trigger workout_plans_touch_updated_at
before update on public.workout_plans
for each row execute function public.touch_updated_at();

alter table public.exercise_library enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_plan_exercises enable row level security;
alter table public.workout_assignments enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.workout_set_logs enable row level security;

create function public.can_client_read_exercise(target_exercise_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workout_plan_exercises plan_exercise
    join public.workout_plans plan on plan.id = plan_exercise.plan_id
    join public.workout_assignments assignment on assignment.plan_id = plan.id
    join public.clients client on client.id = assignment.client_id
    where plan_exercise.exercise_id = target_exercise_id
      and client.profile_id = (select auth.uid())
      and assignment.is_active
  );
$$;

revoke all on function public.can_client_read_exercise(uuid) from public;
grant execute on function public.can_client_read_exercise(uuid) to authenticated;

create policy exercise_library_read_available
on public.exercise_library for select to authenticated
using (
  trainer_id = (select auth.uid())
  or public.can_client_read_exercise(id)
);

create policy exercise_library_trainer_create
on public.exercise_library for insert to authenticated
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'trainer'
  )
);

create policy exercise_library_trainer_update
on public.exercise_library for update to authenticated
using (trainer_id = (select auth.uid()))
with check (trainer_id = (select auth.uid()));

create policy exercise_library_trainer_delete
on public.exercise_library for delete to authenticated
using (trainer_id = (select auth.uid()));

create policy workout_plans_read_available
on public.workout_plans for select to authenticated
using (
  trainer_id = (select auth.uid())
  or exists (
    select 1
    from public.workout_assignments assignment
    join public.clients client on client.id = assignment.client_id
    where assignment.plan_id = workout_plans.id
      and assignment.is_active
      and client.profile_id = (select auth.uid())
  )
);

create policy workout_plans_trainer_create
on public.workout_plans for insert to authenticated
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'trainer'
  )
);

create policy workout_plans_trainer_update
on public.workout_plans for update to authenticated
using (trainer_id = (select auth.uid()))
with check (trainer_id = (select auth.uid()));

create policy workout_plans_trainer_delete
on public.workout_plans for delete to authenticated
using (trainer_id = (select auth.uid()));

create policy workout_plan_exercises_read_assigned
on public.workout_plan_exercises for select to authenticated
using (
  exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id
      and (
        plan.trainer_id = (select auth.uid())
        or exists (
          select 1
          from public.workout_assignments assignment
          join public.clients client on client.id = assignment.client_id
          where assignment.plan_id = plan.id
            and assignment.is_active
            and client.profile_id = (select auth.uid())
        )
      )
  )
);

create policy workout_plan_exercises_trainer_create
on public.workout_plan_exercises for insert to authenticated
with check (
  exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id and plan.trainer_id = (select auth.uid())
  )
);

create policy workout_plan_exercises_trainer_update
on public.workout_plan_exercises for update to authenticated
using (
  exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id and plan.trainer_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id and plan.trainer_id = (select auth.uid())
  )
);

create policy workout_plan_exercises_trainer_delete
on public.workout_plan_exercises for delete to authenticated
using (
  exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id and plan.trainer_id = (select auth.uid())
  )
);

create policy workout_assignments_read_owned
on public.workout_assignments for select to authenticated
using (
  trainer_id = (select auth.uid())
  or exists (
    select 1 from public.clients client
    where client.id = client_id and client.profile_id = (select auth.uid())
  )
);

create policy workout_assignments_trainer_create
on public.workout_assignments for insert to authenticated
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.clients client
    where client.id = client_id and client.trainer_id = (select auth.uid())
  )
  and exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id and plan.trainer_id = (select auth.uid())
  )
);

create policy workout_assignments_trainer_update
on public.workout_assignments for update to authenticated
using (trainer_id = (select auth.uid()))
with check (
  trainer_id = (select auth.uid())
  and exists (
    select 1 from public.clients client
    where client.id = client_id and client.trainer_id = (select auth.uid())
  )
  and exists (
    select 1 from public.workout_plans plan
    where plan.id = plan_id and plan.trainer_id = (select auth.uid())
  )
);

create policy workout_assignments_trainer_delete
on public.workout_assignments for delete to authenticated
using (trainer_id = (select auth.uid()));

create policy workout_sessions_read_owned
on public.workout_sessions for select to authenticated
using (
  exists (
    select 1
    from public.workout_assignments assignment
    join public.clients client on client.id = assignment.client_id
    where assignment.id = workout_sessions.assignment_id
      and workout_sessions.client_id = client.id
      and (client.trainer_id = (select auth.uid()) or client.profile_id = (select auth.uid()))
  )
);

create policy workout_sessions_client_create
on public.workout_sessions for insert to authenticated
with check (
  status = 'active'
  and completed_at is null
  and exists (
    select 1
    from public.workout_assignments assignment
    join public.clients client on client.id = assignment.client_id
    where assignment.id = workout_sessions.assignment_id
      and assignment.client_id = workout_sessions.client_id
      and assignment.is_active
      and client.status = 'active'
      and client.profile_id = (select auth.uid())
  )
);

create policy workout_sessions_client_update
on public.workout_sessions for update to authenticated
using (
  status = 'active'
  and exists (
    select 1
    from public.workout_assignments assignment
    join public.clients client on client.id = assignment.client_id
    where assignment.id = workout_sessions.assignment_id
      and assignment.client_id = workout_sessions.client_id
      and client.profile_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.workout_assignments assignment
    join public.clients client on client.id = assignment.client_id
    where assignment.id = workout_sessions.assignment_id
      and assignment.client_id = workout_sessions.client_id
      and client.profile_id = (select auth.uid())
  )
);

create policy workout_set_logs_read_owned
on public.workout_set_logs for select to authenticated
using (
  exists (
    select 1
    from public.workout_sessions session
    join public.workout_assignments assignment on assignment.id = session.assignment_id
    join public.clients client on client.id = assignment.client_id
    where session.id = workout_set_logs.session_id
      and (client.trainer_id = (select auth.uid()) or client.profile_id = (select auth.uid()))
  )
);

create policy workout_set_logs_client_create
on public.workout_set_logs for insert to authenticated
with check (
  exists (
    select 1
    from public.workout_sessions session
    join public.workout_assignments assignment on assignment.id = session.assignment_id
    join public.clients client on client.id = assignment.client_id
    join public.workout_plan_exercises plan_exercise on plan_exercise.id = workout_set_logs.plan_exercise_id
    where session.id = workout_set_logs.session_id
      and session.status = 'active'
      and session.client_id = client.id
      and assignment.is_active
      and client.status = 'active'
      and plan_exercise.plan_id = assignment.plan_id
      and plan_exercise.id = workout_set_logs.plan_exercise_id
      and client.profile_id = (select auth.uid())
  )
);

alter publication supabase_realtime add table
  public.exercise_library,
  public.workout_plans,
  public.workout_plan_exercises,
  public.workout_assignments,
  public.workout_sessions,
  public.workout_set_logs;

grant select, insert, update, delete on public.exercise_library to authenticated;
grant select, insert, update, delete on public.workout_plans to authenticated;
grant select, insert, update, delete on public.workout_plan_exercises to authenticated;
grant select, insert, update, delete on public.workout_assignments to authenticated;
grant select on public.workout_sessions to authenticated;
grant insert (id, assignment_id, client_id, started_at) on public.workout_sessions to authenticated;
grant update (status, completed_at) on public.workout_sessions to authenticated;
grant select, insert on public.workout_set_logs to authenticated;
grant all on public.exercise_library, public.workout_plans, public.workout_plan_exercises,
  public.workout_assignments, public.workout_sessions, public.workout_set_logs to service_role;

comment on table public.workout_set_logs is 'Client-generated UUIDs make workout set retries idempotent during offline sync.';