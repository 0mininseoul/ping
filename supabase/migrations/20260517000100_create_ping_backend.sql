create extension if not exists pgcrypto with schema extensions;

create schema if not exists ping_private;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    nickname text not null check (length(trim(nickname)) > 0),
    searchable_nickname text not null check (length(trim(searchable_nickname)) > 0),
    last_used_room_id uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.rooms (
    id uuid primary key default extensions.gen_random_uuid(),
    name text not null check (length(trim(name)) > 0),
    searchable_name text not null check (length(trim(searchable_name)) > 0),
    owner_uid uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'open' check (status in ('open', 'full')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'profiles_last_used_room_id_fkey'
          and conrelid = 'public.profiles'::regclass
    ) then
        alter table public.profiles
            add constraint profiles_last_used_room_id_fkey
            foreign key (last_used_room_id) references public.rooms(id) on delete set null;
    end if;
end;
$$;

create table if not exists public.room_members (
    room_id uuid not null references public.rooms(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    nickname text not null check (length(trim(nickname)) > 0),
    role text not null default 'member' check (role in ('owner', 'member')),
    created_at timestamptz not null default now(),
    primary key (room_id, user_id)
);

create table if not exists public.invitations (
    id uuid primary key default extensions.gen_random_uuid(),
    from_uid uuid not null references public.profiles(id) on delete cascade,
    to_uid uuid not null references public.profiles(id) on delete cascade,
    room_id uuid not null references public.rooms(id) on delete cascade,
    from_nickname text not null check (length(trim(from_nickname)) > 0),
    room_name text not null check (length(trim(room_name)) > 0),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '7 days'),
    check (from_uid <> to_uid)
);

create table if not exists public.invite_links (
    token text primary key default encode(extensions.gen_random_bytes(8), 'hex'),
    room_id uuid not null references public.rooms(id) on delete cascade,
    inviter_uid uuid not null references public.profiles(id) on delete cascade,
    inviter_nickname text not null check (length(trim(inviter_nickname)) > 0),
    room_name text not null check (length(trim(room_name)) > 0),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '7 days'),
    accepted_by uuid references public.profiles(id) on delete set null,
    accepted_at timestamptz,
    check (length(token) >= 8)
);

create table if not exists public.messages (
    id uuid primary key default extensions.gen_random_uuid(),
    room_id uuid not null references public.rooms(id) on delete cascade,
    sender_uid uuid not null references public.profiles(id) on delete cascade,
    receiver_uid uuid not null references public.profiles(id) on delete cascade,
    sender_nickname text not null check (length(trim(sender_nickname)) > 0),
    video_id text not null check (length(trim(video_id)) > 0),
    video_url text not null check (length(trim(video_url)) > 0),
    duration_ms integer not null default 2000 check (duration_ms > 0),
    x_ratio double precision not null check (x_ratio >= 0 and x_ratio <= 1),
    y_ratio double precision not null check (y_ratio >= 0 and y_ratio <= 1),
    status text not null default 'uploaded' check (status in ('uploaded', 'seen')),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '1 day'),
    check (sender_uid <> receiver_uid)
);

create index if not exists profiles_searchable_nickname_idx
    on public.profiles (searchable_nickname text_pattern_ops);
create index if not exists profiles_created_at_idx
    on public.profiles (created_at desc);

create index if not exists rooms_open_searchable_name_idx
    on public.rooms (searchable_name text_pattern_ops, created_at desc)
    where status = 'open';
create index if not exists rooms_owner_uid_idx
    on public.rooms (owner_uid);
create index if not exists rooms_status_created_at_idx
    on public.rooms (status, created_at desc);

create index if not exists room_members_user_id_idx
    on public.room_members (user_id, created_at desc);
create index if not exists room_members_room_id_idx
    on public.room_members (room_id, created_at);

create index if not exists invitations_incoming_idx
    on public.invitations (to_uid, expires_at desc, created_at desc);
create index if not exists invitations_room_idx
    on public.invitations (room_id);
create index if not exists invitations_from_uid_idx
    on public.invitations (from_uid, created_at desc);

create index if not exists invite_links_room_idx
    on public.invite_links (room_id, created_at desc);
create index if not exists invite_links_inviter_idx
    on public.invite_links (inviter_uid, created_at desc);
create index if not exists invite_links_available_idx
    on public.invite_links (expires_at desc)
    where accepted_by is null;

create index if not exists messages_incoming_poll_idx
    on public.messages (receiver_uid, status, expires_at desc, created_at desc);
create index if not exists messages_sender_created_at_idx
    on public.messages (sender_uid, created_at desc);
create index if not exists messages_room_created_at_idx
    on public.messages (room_id, created_at desc);
create index if not exists messages_video_url_idx
    on public.messages (video_url);
create index if not exists messages_expiration_idx
    on public.messages (expires_at);

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.invitations enable row level security;
alter table public.invite_links enable row level security;
alter table public.messages enable row level security;

drop policy if exists "Profiles are readable by authenticated users" on public.profiles;
create policy "Profiles are readable by authenticated users"
    on public.profiles for select
    to authenticated
    using (true);

drop policy if exists "Users insert their own profile" on public.profiles;
create policy "Users insert their own profile"
    on public.profiles for insert
    to authenticated
    with check (id = auth.uid());

drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile"
    on public.profiles for update
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

drop policy if exists "Rooms are visible to members and as open rooms" on public.rooms;
create policy "Rooms are visible to members and as open rooms"
    on public.rooms for select
    to authenticated
    using (
        status = 'open'
        or owner_uid = auth.uid()
        or id in (
            select room_members.room_id
            from public.room_members
            where room_members.user_id = auth.uid()
        )
    );

drop policy if exists "Owners can insert rooms" on public.rooms;
drop policy if exists "Owners can update rooms" on public.rooms;

drop policy if exists "Users can see their memberships" on public.room_members;
create policy "Users can see their memberships"
    on public.room_members for select
    to authenticated
    using (user_id = auth.uid());

drop policy if exists "Users can insert their memberships" on public.room_members;
drop policy if exists "Users can delete their memberships" on public.room_members;

drop policy if exists "Users can see related invitations" on public.invitations;
create policy "Users can see related invitations"
    on public.invitations for select
    to authenticated
    using (from_uid = auth.uid() or to_uid = auth.uid());

drop policy if exists "Users can create sent invitations" on public.invitations;
drop policy if exists "Recipients and senders can delete invitations" on public.invitations;

drop policy if exists "Users can see own invite links" on public.invite_links;
create policy "Users can see own invite links"
    on public.invite_links for select
    to authenticated
    using (inviter_uid = auth.uid() or accepted_by = auth.uid());

drop policy if exists "Users can see related messages" on public.messages;
create policy "Users can see related messages"
    on public.messages for select
    to authenticated
    using (sender_uid = auth.uid() or receiver_uid = auth.uid());

drop policy if exists "Users can create sent messages" on public.messages;
drop policy if exists "Receivers can mark messages seen" on public.messages;

create or replace function ping_private.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function ping_private.set_updated_at();

drop trigger if exists rooms_set_updated_at on public.rooms;
create trigger rooms_set_updated_at
    before update on public.rooms
    for each row execute function ping_private.set_updated_at();

create or replace function ping_private.require_uid()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := auth.uid();
    if current_uid is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    return current_uid;
end;
$$;

create or replace function ping_private.profile_rows(target_uid uuid)
returns table (
    id text,
    nickname text,
    searchable_nickname text,
    rooms text[],
    last_used_room_id text,
    created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
    select
        p.id::text,
        p.nickname,
        p.searchable_nickname,
        coalesce(array_agg(rm.room_id::text order by rm.created_at) filter (where rm.room_id is not null), array[]::text[]),
        p.last_used_room_id::text,
        p.created_at
    from public.profiles p
    left join public.room_members rm on rm.user_id = p.id
    where p.id = target_uid
    group by p.id, p.nickname, p.searchable_nickname, p.last_used_room_id, p.created_at;
$$;

create or replace function ping_private.room_summary_rows(target_room_ids uuid[] default null)
returns table (
    id text,
    name text,
    searchable_name text,
    owner_uid text,
    member_uids text[],
    member_nicknames jsonb,
    status text,
    created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
    select
        r.id::text,
        r.name,
        r.searchable_name,
        r.owner_uid::text,
        coalesce(array_agg(rm.user_id::text order by rm.created_at) filter (where rm.user_id is not null), array[]::text[]),
        coalesce(jsonb_object_agg(rm.user_id::text, rm.nickname) filter (where rm.user_id is not null), '{}'::jsonb),
        r.status,
        r.created_at
    from public.rooms r
    left join public.room_members rm on rm.room_id = r.id
    where target_room_ids is null or r.id = any(target_room_ids)
    group by r.id, r.name, r.searchable_name, r.owner_uid, r.status, r.created_at;
$$;

create or replace function ping_private.ensure_profile(profile_uid uuid, nickname_text text)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.profiles (id, nickname, searchable_nickname)
    values (profile_uid, nickname_text, nickname_text)
    on conflict (id) do nothing;
$$;

create or replace function public.ping_get_profile(target_uid uuid default auth.uid())
returns table (
    id text,
    nickname text,
    searchable_nickname text,
    rooms text[],
    last_used_room_id text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    perform ping_private.require_uid();
    return query
        select *
        from ping_private.profile_rows(coalesce(target_uid, auth.uid()));
end;
$$;

create or replace function public.ping_upsert_profile(nickname_text text, searchable_nickname_text text)
returns table (
    id text,
    nickname text,
    searchable_nickname text,
    rooms text[],
    last_used_room_id text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    insert into public.profiles (id, nickname, searchable_nickname)
    values (current_uid, nickname_text, searchable_nickname_text)
    on conflict on constraint profiles_pkey do update
    set nickname = excluded.nickname,
        searchable_nickname = excluded.searchable_nickname;

    return query
        select *
        from ping_private.profile_rows(current_uid);
end;
$$;

create or replace function public.ping_create_room(room_name text, searchable_room_name text, owner_nickname text)
returns table (
    id text,
    name text,
    searchable_name text,
    owner_uid text,
    member_uids text[],
    member_nicknames jsonb,
    status text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    new_room_id uuid;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, owner_nickname);

    insert into public.rooms as inserted_room (name, searchable_name, owner_uid, status)
    values (room_name, searchable_room_name, current_uid, 'open')
    returning inserted_room.id into new_room_id;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (new_room_id, current_uid, owner_nickname, 'owner');

    update public.profiles
    set last_used_room_id = new_room_id
    where profiles.id = current_uid;

    return query
        select *
        from ping_private.room_summary_rows(array[new_room_id]);
end;
$$;

create or replace function public.ping_my_rooms()
returns table (
    id text,
    name text,
    searchable_name text,
    owner_uid text,
    member_uids text[],
    member_nicknames jsonb,
    status text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select rs.*
        from ping_private.room_summary_rows(
            array(
                select rm.room_id
                from public.room_members rm
                where rm.user_id = current_uid
            )
        ) rs
        order by rs.name;
end;
$$;

create or replace function public.ping_search_open_rooms(search_prefix text)
returns table (
    id text,
    name text,
    searchable_name text,
    owner_uid text,
    member_uids text[],
    member_nicknames jsonb,
    status text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    perform ping_private.require_uid();

    if coalesce(search_prefix, '') = '' then
        return;
    end if;

    return query
        select rs.*
        from ping_private.room_summary_rows(
            array(
                select r.id
                from public.rooms r
                where r.status = 'open'
                  and r.searchable_name like search_prefix || '%'
                order by r.created_at desc
                limit 20
            )
        ) rs
        order by rs.created_at desc;
end;
$$;

create or replace function public.ping_join_room(room_uuid uuid, nickname_text text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    current_count integer;
    room_row public.rooms%rowtype;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, nickname_text);

    select *
    into room_row
    from public.rooms
    where rooms.id = room_uuid
    for update;

    if not found then
        raise exception 'room_not_found' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) then
        update public.room_members
        set nickname = nickname_text
        where room_id = room_uuid and user_id = current_uid;
    else
        select count(*) into current_count
        from public.room_members
        where room_id = room_uuid;

        if room_row.status <> 'open' or current_count >= 2 then
            raise exception 'room_unavailable' using errcode = '23514';
        end if;

        insert into public.room_members (room_id, user_id, nickname, role)
        values (room_uuid, current_uid, nickname_text, 'member');
    end if;

    select count(*) into current_count
    from public.room_members
    where room_id = room_uuid;

    update public.rooms
    set status = case when current_count >= 2 then 'full' else 'open' end
    where rooms.id = room_uuid;

    update public.profiles
    set last_used_room_id = room_uuid
    where profiles.id = current_uid;
end;
$$;

create or replace function public.ping_leave_room(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    remaining_count integer;
    next_owner uuid;
begin
    current_uid := ping_private.require_uid();

    if not exists (
        select 1
        from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) then
        return;
    end if;

    delete from public.room_members
    where room_id = room_uuid and user_id = current_uid;

    update public.profiles
    set last_used_room_id = null
    where profiles.id = current_uid
      and profiles.last_used_room_id = room_uuid;

    select count(*) into remaining_count
    from public.room_members
    where room_id = room_uuid;

    if remaining_count = 0 then
        delete from public.rooms where rooms.id = room_uuid;
        return;
    end if;

    select user_id into next_owner
    from public.room_members
    where room_id = room_uuid
    order by created_at
    limit 1;

    update public.rooms
    set owner_uid = case when owner_uid = current_uid then next_owner else owner_uid end,
        status = 'open'
    where rooms.id = room_uuid;

    update public.room_members
    set role = case when user_id = (select owner_uid from public.rooms where id = room_uuid) then 'owner' else 'member' end
    where room_id = room_uuid;
end;
$$;

create or replace function public.ping_rename_room(room_uuid uuid, new_name text, new_searchable_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    update public.rooms
    set name = new_name,
        searchable_name = new_searchable_name
    where rooms.id = room_uuid
      and rooms.owner_uid = current_uid;

    if not found then
        raise exception 'room_not_found_or_not_owner' using errcode = '42501';
    end if;
end;
$$;

create or replace function public.ping_search_profiles(search_prefix text)
returns table (
    id text,
    nickname text,
    searchable_nickname text,
    rooms text[],
    last_used_room_id text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    if coalesce(search_prefix, '') = '' then
        return;
    end if;

    return query
        select pr.*
        from (
            select p.id
            from public.profiles p
            where p.id <> current_uid
              and p.searchable_nickname like search_prefix || '%'
            order by p.created_at desc
            limit 20
        ) matches
        cross join lateral ping_private.profile_rows(matches.id) pr;
end;
$$;

create or replace function public.ping_update_last_used_room(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    if not exists (
        select 1
        from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) then
        raise exception 'not_room_member' using errcode = '42501';
    end if;

    update public.profiles
    set last_used_room_id = room_uuid
    where id = current_uid;
end;
$$;

create or replace function public.ping_send_invitation(
    to_uid uuid,
    room_uuid uuid,
    from_nickname text,
    room_name_text text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    member_count integer;
    invitation_id uuid;
begin
    current_uid := ping_private.require_uid();

    if to_uid = current_uid then
        raise exception 'cannot_invite_self' using errcode = '23514';
    end if;

    if not exists (select 1 from public.profiles where id = to_uid) then
        raise exception 'profile_not_found' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) then
        raise exception 'not_room_member' using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.room_members
        where room_id = room_uuid and user_id = to_uid
    ) then
        raise exception 'already_room_member' using errcode = '23505';
    end if;

    select count(*) into member_count
    from public.room_members
    where room_id = room_uuid;

    if member_count >= 2 then
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.invitations (from_uid, to_uid, room_id, from_nickname, room_name)
    values (current_uid, to_uid, room_uuid, from_nickname, room_name_text)
    returning id into invitation_id;

    return invitation_id;
end;
$$;

create or replace function public.ping_incoming_invitations()
returns table (
    id text,
    from_uid text,
    to_uid text,
    room_id text,
    from_nickname text,
    room_name text,
    created_at timestamptz,
    expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select
            i.id::text,
            i.from_uid::text,
            i.to_uid::text,
            i.room_id::text,
            i.from_nickname,
            i.room_name,
            i.created_at,
            i.expires_at
        from public.invitations i
        where i.to_uid = current_uid
          and i.expires_at > now()
        order by i.created_at desc;
end;
$$;

create or replace function public.ping_accept_invitation(invitation_uuid uuid, nickname_text text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    invitation_row public.invitations%rowtype;
    current_count integer;
    room_row public.rooms%rowtype;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, nickname_text);

    select *
    into invitation_row
    from public.invitations
    where id = invitation_uuid
      and to_uid = current_uid
      and expires_at > now()
    for update;

    if not found then
        raise exception 'invitation_not_found' using errcode = 'P0002';
    end if;

    select *
    into room_row
    from public.rooms
    where id = invitation_row.room_id
    for update;

    if not found then
        delete from public.invitations where id = invitation_uuid;
        raise exception 'room_not_found' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.room_members
        where room_id = invitation_row.room_id and user_id = current_uid
    ) then
        delete from public.invitations where id = invitation_uuid;
        return;
    end if;

    select count(*) into current_count
    from public.room_members
    where room_id = invitation_row.room_id;

    if room_row.status <> 'open' or current_count >= 2 then
        delete from public.invitations where id = invitation_uuid;
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (invitation_row.room_id, current_uid, nickname_text, 'member');

    update public.rooms
    set status = 'full'
    where id = invitation_row.room_id;

    update public.profiles
    set last_used_room_id = invitation_row.room_id
    where id = current_uid;

    delete from public.invitations where id = invitation_uuid;
end;
$$;

create or replace function public.ping_create_invite_link(room_uuid uuid)
returns table (
    token text,
    room_id text,
    room_name text,
    inviter_nickname text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    member_count integer;
    link_token text;
begin
    current_uid := ping_private.require_uid();

    if not exists (
        select 1
        from public.room_members rm_check
        where rm_check.room_id = room_uuid and rm_check.user_id = current_uid
    ) then
        raise exception 'not_room_member' using errcode = '42501';
    end if;

    select count(*) into member_count
    from public.room_members rm_count
    where rm_count.room_id = room_uuid;

    if not exists (
        select 1
        from public.rooms
        where id = room_uuid
          and status = 'open'
    ) or member_count >= 2 then
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.invite_links (room_id, inviter_uid, inviter_nickname, room_name)
    select r.id, current_uid, rm.nickname, r.name
    from public.rooms r
    join public.room_members rm on rm.room_id = r.id and rm.user_id = current_uid
    where r.id = room_uuid
    returning invite_links.token into link_token;

    return query
        select
            il.token,
            il.room_id::text,
            il.room_name,
            il.inviter_nickname,
            il.expires_at
        from public.invite_links il
        where il.token = link_token;
end;
$$;

create or replace function public.ping_accept_invite_link(invite_token text, nickname_text text)
returns table (
    id text,
    name text,
    searchable_name text,
    owner_uid text,
    member_uids text[],
    member_nicknames jsonb,
    status text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    link_row public.invite_links%rowtype;
    room_row public.rooms%rowtype;
    current_count integer;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, nickname_text);

    select *
    into link_row
    from public.invite_links
    where invite_links.token = invite_token
      and expires_at > now()
      and accepted_by is null
    for update;

    if not found then
        raise exception 'invite_link_not_found' using errcode = 'P0002';
    end if;

    select *
    into room_row
    from public.rooms
    where id = link_row.room_id
    for update;

    if not found then
        raise exception 'room_not_found' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.room_members
        where room_id = link_row.room_id and user_id = current_uid
    ) then
        update public.profiles
        set last_used_room_id = link_row.room_id
        where id = current_uid;

        return query
            select *
            from ping_private.room_summary_rows(array[link_row.room_id]);
        return;
    end if;

    if current_uid = link_row.inviter_uid then
        return query
            select *
            from ping_private.room_summary_rows(array[link_row.room_id]);
        return;
    end if;

    select count(*) into current_count
    from public.room_members
    where room_id = link_row.room_id;

    if room_row.status <> 'open' or current_count >= 2 then
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (link_row.room_id, current_uid, nickname_text, 'member');

    update public.rooms
    set status = 'full'
    where id = link_row.room_id;

    update public.profiles
    set last_used_room_id = link_row.room_id
    where id = current_uid;

    update public.invite_links
    set accepted_by = current_uid,
        accepted_at = now()
    where invite_links.token = invite_token;

    return query
        select *
        from ping_private.room_summary_rows(array[link_row.room_id]);
end;
$$;

create or replace function public.ping_reject_invitation(invitation_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    delete from public.invitations
    where id = invitation_uuid
      and to_uid = current_uid;
end;
$$;

create or replace function public.ping_create_message(
    room_uuid uuid,
    receiver_uid uuid,
    sender_nickname_text text,
    video_id_text text,
    video_url_text text,
    x_ratio double precision,
    y_ratio double precision
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    message_id uuid;
begin
    current_uid := ping_private.require_uid();

    if receiver_uid = current_uid then
        raise exception 'cannot_send_to_self' using errcode = '23514';
    end if;

    if not exists (
        select 1 from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) or not exists (
        select 1 from public.room_members
        where room_id = room_uuid and user_id = receiver_uid
    ) then
        raise exception 'not_room_members' using errcode = '42501';
    end if;

    insert into public.messages (
        room_id,
        sender_uid,
        receiver_uid,
        sender_nickname,
        video_id,
        video_url,
        duration_ms,
        x_ratio,
        y_ratio,
        status,
        expires_at
    )
    values (
        room_uuid,
        current_uid,
        receiver_uid,
        sender_nickname_text,
        video_id_text,
        video_url_text,
        2000,
        x_ratio,
        y_ratio,
        'uploaded',
        now() + interval '1 day'
    )
    returning id into message_id;

    update public.profiles
    set last_used_room_id = room_uuid
    where id = current_uid;

    return message_id;
end;
$$;

create or replace function public.ping_incoming_messages()
returns table (
    id text,
    room_id text,
    sender_uid text,
    receiver_uid text,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select
            m.id::text,
            m.room_id::text,
            m.sender_uid::text,
            m.receiver_uid::text,
            m.sender_nickname,
            m.video_id,
            m.video_url,
            m.duration_ms,
            jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio),
            m.status,
            m.created_at,
            m.expires_at
        from public.messages m
        where m.receiver_uid = current_uid
          and m.status = 'uploaded'
          and m.expires_at > now()
        order by m.created_at desc;
end;
$$;

create or replace function public.ping_get_message(message_uuid uuid)
returns table (
    id text,
    room_id text,
    sender_uid text,
    receiver_uid text,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select
            m.id::text,
            m.room_id::text,
            m.sender_uid::text,
            m.receiver_uid::text,
            m.sender_nickname,
            m.video_id,
            m.video_url,
            m.duration_ms,
            jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio),
            m.status,
            m.created_at,
            m.expires_at
        from public.messages m
        where m.id = message_uuid
          and m.expires_at > now()
          and (
              m.sender_uid = current_uid
              or (m.receiver_uid = current_uid and m.status = 'uploaded')
          );
end;
$$;

create or replace function public.ping_mark_message_seen(message_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    update public.messages
    set status = 'seen'
    where id = message_uuid
      and receiver_uid = current_uid;

    if not found then
        raise exception 'message_not_found' using errcode = 'P0002';
    end if;
end;
$$;

create or replace function public.ping_cleanup_expired_data()
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
    delete from storage.objects o
    where o.bucket_id = 'ping-videos'
      and exists (
          select 1
          from public.messages m
          where m.expires_at <= now()
            and (
                m.video_url = o.name
                or (m.sender_uid::text || '/' || m.video_id || '.mp4') = o.name
            )
      )
      and not exists (
          select 1
          from public.messages m
          where m.expires_at > now()
            and (
                m.video_url = o.name
                or (m.sender_uid::text || '/' || m.video_id || '.mp4') = o.name
            )
      );

    delete from public.messages
    where expires_at <= now();

    delete from public.invitations
    where expires_at <= now();
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ping-videos', 'ping-videos', false, 52428800, array['video/mp4'])
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Ping videos owner upload" on storage.objects;
create policy "Ping videos owner upload"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'ping-videos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "Ping videos owner update" on storage.objects;
create policy "Ping videos owner update"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'ping-videos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "Ping videos owner delete" on storage.objects;
create policy "Ping videos owner delete"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "Ping videos sender receiver read" on storage.objects;
create policy "Ping videos sender receiver read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1
                from public.messages m
                where m.expires_at > now()
                  and m.status = 'uploaded'
                  and m.receiver_uid = auth.uid()
                  and (
                      m.video_url = storage.objects.name
                      or (m.sender_uid::text || '/' || m.video_id || '.mp4') = storage.objects.name
                  )
            )
        )
    );

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.rooms to authenticated;
grant select on public.room_members to authenticated;
grant select on public.invitations to authenticated;
grant select on public.messages to authenticated;

grant execute on function public.ping_get_profile(uuid) to authenticated;
grant execute on function public.ping_upsert_profile(text, text) to authenticated;
grant execute on function public.ping_create_room(text, text, text) to authenticated;
grant execute on function public.ping_my_rooms() to authenticated;
grant execute on function public.ping_search_open_rooms(text) to authenticated;
grant execute on function public.ping_join_room(uuid, text) to authenticated;
grant execute on function public.ping_leave_room(uuid) to authenticated;
grant execute on function public.ping_rename_room(uuid, text, text) to authenticated;
grant execute on function public.ping_search_profiles(text) to authenticated;
grant execute on function public.ping_update_last_used_room(uuid) to authenticated;
grant execute on function public.ping_send_invitation(uuid, uuid, text, text) to authenticated;
grant execute on function public.ping_incoming_invitations() to authenticated;
grant execute on function public.ping_accept_invitation(uuid, text) to authenticated;
grant execute on function public.ping_reject_invitation(uuid) to authenticated;
grant execute on function public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision) to authenticated;
grant execute on function public.ping_incoming_messages() to authenticated;
grant execute on function public.ping_get_message(uuid) to authenticated;
grant execute on function public.ping_mark_message_seen(uuid) to authenticated;
grant execute on function public.ping_cleanup_expired_data() to authenticated;
