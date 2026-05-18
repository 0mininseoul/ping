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

    insert into public.rooms as inserted_room (name, searchable_name, owner_uid, status)
    values (room_name_text, searchable_room_name, current_uid, 'open')
    returning inserted_room.id into new_room_id;

    insert into public.room_members (room_id, user_id, nickname, role)
    values (new_room_id, current_uid, inviter_nickname_text, 'owner');

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

grant execute on function public.ping_invite_user(uuid, text, text, text) to authenticated;
