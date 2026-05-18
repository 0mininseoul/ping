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

grant execute on function public.ping_accept_invite_link(text, text) to authenticated;
