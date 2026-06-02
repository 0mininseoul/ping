alter table public.rooms
    add column if not exists name_is_custom boolean not null default false;

alter table public.rooms
    drop constraint if exists rooms_name_length_limit;

alter table public.rooms
    drop constraint if exists rooms_searchable_name_length_limit;

create or replace function ping_private.searchable_room_name(name_text text)
returns text
language sql
immutable
set search_path = public
as $$
    select lower(regexp_replace(trim(coalesce(name_text, '')), '\s+', ' ', 'g'));
$$;

create or replace function ping_private.room_default_name(room_uuid uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        string_agg(nullif(trim(rm.nickname), ''), ', ' order by rm.created_at, rm.user_id::text),
        ''
    )
    from public.room_members rm
    where rm.room_id = room_uuid;
$$;

create or replace function ping_private.refresh_room_auto_name(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    default_name text;
begin
    select ping_private.room_default_name(room_uuid) into default_name;

    if coalesce(default_name, '') = '' then
        return;
    end if;

    update public.rooms as r_update
    set name = default_name,
        searchable_name = ping_private.searchable_room_name(default_name)
    where r_update.id = room_uuid
      and r_update.name_is_custom = false;
end;
$$;

with room_defaults as (
    select
        r.id,
        r.name,
        ping_private.room_default_name(r.id) as default_name
    from public.rooms r
)
update public.rooms as r_update
set name_is_custom = case
    when coalesce(room_defaults.default_name, '') = '' then true
    when ping_private.searchable_room_name(room_defaults.name) = ping_private.searchable_room_name(room_defaults.default_name) then false
    when position('↔' in room_defaults.name) > 0 then false
    else true
end
from room_defaults
where r_update.id = room_defaults.id;

update public.rooms as r_update
set name = room_defaults.default_name,
    searchable_name = ping_private.searchable_room_name(room_defaults.default_name)
from (
    select r.id, ping_private.room_default_name(r.id) as default_name
    from public.rooms r
) as room_defaults
where r_update.id = room_defaults.id
  and r_update.name_is_custom = false
  and coalesce(room_defaults.default_name, '') <> '';

alter table public.rooms
    add constraint rooms_name_length_limit
    check (
        char_length(btrim(name)) between 1 and
            case when name_is_custom then 48 else 128 end
    ) not valid;

alter table public.rooms
    add constraint rooms_searchable_name_length_limit
    check (
        char_length(btrim(searchable_name)) between 1 and
            case when name_is_custom then 48 else 128 end
    ) not valid;

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
        coalesce(
            case when r.name_is_custom then r.name else nullif(room_defaults.default_name, '') end,
            r.name
        ) as name,
        coalesce(
            case
                when r.name_is_custom then r.searchable_name
                else nullif(ping_private.searchable_room_name(room_defaults.default_name), '')
            end,
            r.searchable_name
        ) as searchable_name,
        r.owner_uid::text,
        coalesce(array_agg(rm.user_id::text order by rm.created_at) filter (where rm.user_id is not null), array[]::text[]),
        coalesce(jsonb_object_agg(rm.user_id::text, rm.nickname) filter (where rm.user_id is not null), '{}'::jsonb),
        r.status,
        r.created_at
    from public.rooms r
    left join lateral (
        select ping_private.room_default_name(r.id) as default_name
    ) as room_defaults on true
    left join public.room_members rm on rm.room_id = r.id
    where target_room_ids is null or r.id = any(target_room_ids)
    group by r.id, r.name, r.searchable_name, r.name_is_custom, room_defaults.default_name, r.owner_uid, r.status, r.created_at;
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
    room_to_refresh uuid;
begin
    current_uid := ping_private.require_uid();

    insert into public.profiles (id, nickname, searchable_nickname)
    values (current_uid, nickname_text, searchable_nickname_text)
    on conflict on constraint profiles_pkey do update
    set nickname = excluded.nickname,
        searchable_nickname = excluded.searchable_nickname;

    update public.room_members
    set nickname = nickname_text
    where user_id = current_uid
      and nickname <> nickname_text;

    for room_to_refresh in
        select room_id
        from public.room_members
        where user_id = current_uid
    loop
        perform ping_private.refresh_room_auto_name(room_to_refresh);
    end loop;

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
    current_room_count integer;
    new_room_id uuid;
    created_name text;
    created_searchable_name text;
    created_is_custom boolean;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, owner_nickname);

    select count(*) into current_room_count
    from public.room_members
    where user_id = current_uid;

    if current_room_count >= 8 then
        raise exception 'room_limit_reached' using errcode = '23514';
    end if;

    created_is_custom := ping_private.searchable_room_name(room_name) <> ping_private.searchable_room_name(owner_nickname);
    created_name := case when created_is_custom then room_name else owner_nickname end;
    created_searchable_name := case
        when created_is_custom then searchable_room_name
        else ping_private.searchable_room_name(owner_nickname)
    end;

    insert into public.rooms as inserted_room (name, searchable_name, owner_uid, status, name_is_custom)
    values (created_name, created_searchable_name, current_uid, 'open', created_is_custom)
    returning inserted_room.id into new_room_id;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (new_room_id, current_uid, owner_nickname, 'owner');

    perform ping_private.refresh_room_auto_name(new_room_id);

    update public.profiles
    set last_used_room_id = new_room_id
    where profiles.id = current_uid;

    return query
        select *
        from ping_private.room_summary_rows(array[new_room_id]);
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
    current_room_count integer;
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
        select count(*) into current_room_count
        from public.room_members
        where user_id = current_uid;

        if current_room_count >= 8 then
            raise exception 'room_limit_reached' using errcode = '23514';
        end if;

        select count(*) into current_count
        from public.room_members
        where room_id = room_uuid;

        if current_count >= 4 then
            raise exception 'room_unavailable' using errcode = '23514';
        end if;

        insert into public.room_members (room_id, user_id, nickname, role)
        values (room_uuid, current_uid, nickname_text, 'member');
    end if;

    select count(*) into current_count
    from public.room_members
    where room_id = room_uuid;

    update public.rooms
    set status = case when current_count >= 4 then 'full' else 'open' end
    where rooms.id = room_uuid;

    perform ping_private.refresh_room_auto_name(room_uuid);

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

    perform ping_private.refresh_room_auto_name(room_uuid);
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

    if not exists (
        select 1
        from public.room_members
        where room_id = room_uuid
          and user_id = current_uid
    ) then
        raise exception 'room_not_found_or_not_member' using errcode = '42501';
    end if;

    update public.rooms
    set name = new_name,
        searchable_name = new_searchable_name,
        name_is_custom = true
    where rooms.id = room_uuid;

    if not found then
        raise exception 'room_not_found_or_not_member' using errcode = '42501';
    end if;
end;
$$;

create or replace function public.ping_invite_user(
    target_uid uuid,
    inviter_nickname_text text,
    room_name_text text,
    searchable_room_name text
)
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
    current_room_count integer;
    invitee_room_count integer;
    new_room_id uuid;
    existing_room_id uuid;
    existing_invitation_id uuid;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, inviter_nickname_text);

    if target_uid = current_uid then
        raise exception 'cannot_invite_self' using errcode = '23514';
    end if;

    if not exists (select 1 from public.profiles where profiles.id = target_uid) then
        raise exception 'profile_not_found' using errcode = 'P0002';
    end if;

    perform pg_advisory_xact_lock(
        hashtextextended(
            least(current_uid::text, target_uid::text) || ':' || greatest(current_uid::text, target_uid::text),
            0
        )
    );

    select rm_self.room_id
    into existing_room_id
    from public.room_members rm_self
    join public.room_members rm_target
      on rm_target.room_id = rm_self.room_id
     and rm_target.user_id = target_uid
    join public.rooms r on r.id = rm_self.room_id
    where rm_self.user_id = current_uid
    order by r.created_at desc
    limit 1;

    if existing_room_id is not null then
        update public.profiles
        set last_used_room_id = existing_room_id
        where profiles.id = current_uid;

        return query
            select *
            from ping_private.room_summary_rows(array[existing_room_id]);
        return;
    end if;

    delete from public.invitations
    where invitations.from_uid = current_uid
      and invitations.to_uid = target_uid
      and invitations.expires_at <= now();

    select i.id, i.room_id
    into existing_invitation_id, existing_room_id
    from public.invitations i
    where i.from_uid = current_uid
      and i.to_uid = target_uid
      and i.expires_at > now()
      and exists (
          select 1
          from public.room_members rm
          where rm.room_id = i.room_id
            and rm.user_id = current_uid
      )
      and not exists (
          select 1
          from public.room_members rm
          where rm.room_id = i.room_id
            and rm.user_id = target_uid
      )
    order by i.created_at desc
    limit 1;

    if existing_invitation_id is not null then
        update public.invitations
        set from_nickname = inviter_nickname_text,
            room_name = room_name_text,
            expires_at = greatest(invitations.expires_at, now() + interval '7 days')
        where invitations.id = existing_invitation_id;

        update public.profiles
        set last_used_room_id = existing_room_id
        where profiles.id = current_uid;

        return query
            select *
            from ping_private.room_summary_rows(array[existing_room_id]);
        return;
    end if;

    select count(*) into current_room_count
    from public.room_members
    where user_id = current_uid;

    if current_room_count >= 8 then
        raise exception 'room_limit_reached' using errcode = '23514';
    end if;

    select count(*) into invitee_room_count
    from public.room_members
    where user_id = target_uid;

    if invitee_room_count >= 8 then
        raise exception 'invitee_room_limit_reached' using errcode = '23514';
    end if;

    insert into public.rooms as inserted_room (name, searchable_name, owner_uid, status, name_is_custom)
    values (
        inviter_nickname_text,
        ping_private.searchable_room_name(inviter_nickname_text),
        current_uid,
        'open',
        false
    )
    returning inserted_room.id into new_room_id;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (new_room_id, current_uid, inviter_nickname_text, 'owner');

    perform ping_private.refresh_room_auto_name(new_room_id);

    insert into public.invitations (from_uid, to_uid, room_id, from_nickname, room_name)
    values (current_uid, target_uid, new_room_id, inviter_nickname_text, room_name_text);

    update public.profiles
    set last_used_room_id = new_room_id
    where profiles.id = current_uid;

    return query
        select *
        from ping_private.room_summary_rows(array[new_room_id]);
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
    current_room_count integer;
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

    select count(*) into current_room_count
    from public.room_members
    where user_id = current_uid;

    if current_room_count >= 8 then
        delete from public.invitations where id = invitation_uuid;
        raise exception 'room_limit_reached' using errcode = '23514';
    end if;

    select count(*) into current_count
    from public.room_members
    where room_id = invitation_row.room_id;

    if current_count >= 4 then
        delete from public.invitations where id = invitation_uuid;
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (invitation_row.room_id, current_uid, nickname_text, 'member');

    select count(*) into current_count
    from public.room_members
    where room_id = invitation_row.room_id;

    update public.rooms
    set status = case when current_count >= 4 then 'full' else 'open' end
    where id = invitation_row.room_id;

    perform ping_private.refresh_room_auto_name(invitation_row.room_id);

    update public.profiles
    set last_used_room_id = invitation_row.room_id
    where id = current_uid;

    delete from public.invitations where id = invitation_uuid;
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
    current_room_count integer;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, nickname_text);

    select il_accept.*
    into link_row
    from public.invite_links il_accept
    where il_accept.token = invite_token
      and il_accept.expires_at > now()
    for update;

    if not found then
        raise exception 'invite_link_not_found' using errcode = 'P0002';
    end if;

    select r_accept.*
    into room_row
    from public.rooms r_accept
    where r_accept.id = link_row.room_id
    for update;

    if not found then
        raise exception 'room_not_found' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.room_members rm_existing
        where rm_existing.room_id = link_row.room_id and rm_existing.user_id = current_uid
    ) then
        update public.profiles p_accept
        set last_used_room_id = link_row.room_id
        where p_accept.id = current_uid;

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

    select count(*) into current_room_count
    from public.room_members rm_user_count
    where rm_user_count.user_id = current_uid;

    if current_room_count >= 8 then
        raise exception 'room_limit_reached' using errcode = '23514';
    end if;

    select count(*) into current_count
    from public.room_members rm_room_count
    where rm_room_count.room_id = link_row.room_id;

    if current_count >= 4 then
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (link_row.room_id, current_uid, nickname_text, 'member');

    select count(*) into current_count
    from public.room_members rm_room_count_after_insert
    where rm_room_count_after_insert.room_id = link_row.room_id;

    update public.rooms r_update
    set status = case when current_count >= 4 then 'full' else 'open' end
    where r_update.id = link_row.room_id;

    perform ping_private.refresh_room_auto_name(link_row.room_id);

    update public.profiles p_update
    set last_used_room_id = link_row.room_id
    where p_update.id = current_uid;

    update public.invite_links il_update
    set accepted_by = coalesce(il_update.accepted_by, current_uid),
        accepted_at = coalesce(il_update.accepted_at, now())
    where il_update.token = invite_token;

    return query
        select *
        from ping_private.room_summary_rows(array[link_row.room_id]);
end;
$$;

grant execute on function public.ping_upsert_profile(text, text) to authenticated;
grant execute on function public.ping_create_room(text, text, text) to authenticated;
grant execute on function public.ping_join_room(uuid, text) to authenticated;
grant execute on function public.ping_leave_room(uuid) to authenticated;
grant execute on function public.ping_rename_room(uuid, text, text) to authenticated;
grant execute on function public.ping_invite_user(uuid, text, text, text) to authenticated;
grant execute on function public.ping_accept_invitation(uuid, text) to authenticated;
grant execute on function public.ping_accept_invite_link(text, text) to authenticated;
