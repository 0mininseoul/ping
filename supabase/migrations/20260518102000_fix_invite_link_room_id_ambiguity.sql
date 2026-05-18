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

grant execute on function public.ping_create_invite_link(uuid) to authenticated;
