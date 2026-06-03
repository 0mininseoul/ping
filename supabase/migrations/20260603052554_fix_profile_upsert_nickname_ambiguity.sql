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

    update public.room_members as rm_profile
    set nickname = nickname_text
    where rm_profile.user_id = current_uid
      and rm_profile.nickname <> nickname_text;

    for room_to_refresh in
        select rm_refresh.room_id
        from public.room_members as rm_refresh
        where rm_refresh.user_id = current_uid
    loop
        perform ping_private.refresh_room_auto_name(room_to_refresh);
    end loop;

    return query
        select *
        from ping_private.profile_rows(current_uid);
end;
$$;

grant execute on function public.ping_upsert_profile(text, text) to authenticated;
