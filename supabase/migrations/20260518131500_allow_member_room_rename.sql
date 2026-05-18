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
        searchable_name = new_searchable_name
    where rooms.id = room_uuid;

    if not found then
        raise exception 'room_not_found_or_not_member' using errcode = '42501';
    end if;
end;
$$;

grant execute on function public.ping_rename_room(uuid, text, text) to authenticated;
