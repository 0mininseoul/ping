-- Client-side event tracking for product analytics.
-- Anonymous UID only; no PII. User's data lives on user's Supabase.

create table if not exists public.client_events (
    id uuid primary key default gen_random_uuid(),
    uid uuid references public.profiles(id) on delete set null,
    event_name text not null check (char_length(event_name) <= 64),
    properties jsonb not null default '{}'::jsonb,
    app_version text,
    os_version text,
    created_at timestamptz not null default now()
);

create index if not exists client_events_event_name_created_at_idx
    on public.client_events (event_name, created_at desc);
create index if not exists client_events_uid_created_at_idx
    on public.client_events (uid, created_at desc);

alter table public.client_events enable row level security;

-- Users can insert their own events
create policy client_events_insert_own
    on public.client_events
    for insert
    to authenticated
    with check (uid = auth.uid());

-- Users can read their own events (for debug/transparency)
create policy client_events_select_own
    on public.client_events
    for select
    to authenticated
    using (uid = auth.uid());

-- RPC for batched / typed event insertion
create or replace function public.ping_log_event(
    event_name_text text,
    properties_jsonb jsonb default '{}'::jsonb,
    app_version_text text default null,
    os_version_text text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    new_id uuid;
begin
    current_uid := auth.uid();
    if current_uid is null then
        raise exception 'auth required';
    end if;
    if event_name_text is null or char_length(event_name_text) = 0 or char_length(event_name_text) > 64 then
        raise exception 'invalid event_name';
    end if;

    insert into public.client_events(uid, event_name, properties, app_version, os_version)
    values (current_uid, event_name_text, coalesce(properties_jsonb, '{}'::jsonb), app_version_text, os_version_text)
    returning id into new_id;

    return new_id;
end;
$$;

grant execute on function public.ping_log_event(text, jsonb, text, text) to authenticated;

-- Cleanup: 90 days retention for events (longer than messages because aggregate analytics need time depth)
-- We piggy-back on ping_cleanup_expired_data without altering its signature; if needed we extend it later.
