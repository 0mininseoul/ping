-- Allow each user to participate in up to 8 rooms, and each room to hold up to 4 members.

update public.rooms r
set status = case when counts.member_count >= 4 then 'full' else 'open' end
from (
    select room_id, count(*) as member_count
    from public.room_members
    group by room_id
) counts
where r.id = counts.room_id;

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
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, owner_nickname);

    select count(*) into current_room_count
    from public.room_members
    where user_id = current_uid;

    if current_room_count >= 8 then
        raise exception 'room_limit_reached' using errcode = '23514';
    end if;

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

    update public.profiles
    set last_used_room_id = room_uuid
    where profiles.id = current_uid;
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
    invitee_room_count integer;
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

    if member_count >= 4 then
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    select count(*) into invitee_room_count
    from public.room_members
    where user_id = to_uid;

    if invitee_room_count >= 8 then
        raise exception 'invitee_room_limit_reached' using errcode = '23514';
    end if;

    insert into public.invitations (from_uid, to_uid, room_id, from_nickname, room_name)
    values (current_uid, to_uid, room_uuid, from_nickname, room_name_text)
    returning id into invitation_id;

    return invitation_id;
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
        from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) then
        raise exception 'not_room_member' using errcode = '42501';
    end if;

    select count(*) into member_count
    from public.room_members
    where room_id = room_uuid;

    if member_count >= 4 then
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
    current_room_count integer;
begin
    current_uid := ping_private.require_uid();
    perform ping_private.ensure_profile(current_uid, nickname_text);

    select *
    into link_row
    from public.invite_links
    where invite_links.token = invite_token
      and expires_at > now()
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

    select count(*) into current_room_count
    from public.room_members
    where user_id = current_uid;

    if current_room_count >= 8 then
        raise exception 'room_limit_reached' using errcode = '23514';
    end if;

    select count(*) into current_count
    from public.room_members
    where room_id = link_row.room_id;

    if current_count >= 4 then
        raise exception 'room_unavailable' using errcode = '23514';
    end if;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (link_row.room_id, current_uid, nickname_text, 'member');

    select count(*) into current_count
    from public.room_members
    where room_id = link_row.room_id;

    update public.rooms
    set status = case when current_count >= 4 then 'full' else 'open' end
    where id = link_row.room_id;

    update public.profiles
    set last_used_room_id = link_row.room_id
    where id = current_uid;

    update public.invite_links
    set accepted_by = coalesce(accepted_by, current_uid),
        accepted_at = coalesce(accepted_at, now())
    where invite_links.token = invite_token;

    return query
        select *
        from ping_private.room_summary_rows(array[link_row.room_id]);
end;
$$;

grant execute on function public.ping_create_room(text, text, text) to authenticated;
grant execute on function public.ping_join_room(uuid, text) to authenticated;
grant execute on function public.ping_send_invitation(uuid, uuid, text, text) to authenticated;
grant execute on function public.ping_accept_invitation(uuid, text) to authenticated;
grant execute on function public.ping_create_invite_link(uuid) to authenticated;
grant execute on function public.ping_accept_invite_link(text, text) to authenticated;
