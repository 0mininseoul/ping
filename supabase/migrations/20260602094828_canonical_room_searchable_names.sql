create or replace function ping_private.searchable_room_name(name_text text)
returns text
language sql
immutable
set search_path = public
as $$
    select lower(regexp_replace(trim(coalesce(name_text, '')), '\s+', '', 'g'));
$$;

update public.rooms as r_update
set searchable_name = ping_private.searchable_room_name(r_update.name)
where r_update.name_is_custom = false;
