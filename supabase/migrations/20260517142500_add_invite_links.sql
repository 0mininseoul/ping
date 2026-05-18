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

create index if not exists invite_links_room_idx
    on public.invite_links (room_id, created_at desc);
create index if not exists invite_links_inviter_idx
    on public.invite_links (inviter_uid, created_at desc);
create index if not exists invite_links_available_idx
    on public.invite_links (expires_at desc)
    where accepted_by is null;

alter table public.invite_links enable row level security;

drop policy if exists "Users can see own invite links" on public.invite_links;
create policy "Users can see own invite links"
    on public.invite_links for select
    to authenticated
    using (inviter_uid = auth.uid() or accepted_by = auth.uid());

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
