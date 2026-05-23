-- v0.3.16: keep room names compact enough for the macOS room sidebar.
-- NOT VALID preserves existing long room names while enforcing the limit for new writes.

alter table public.rooms
    drop constraint if exists rooms_name_length_limit;

alter table public.rooms
    add constraint rooms_name_length_limit
    check (char_length(btrim(name)) between 1 and 16)
    not valid;

alter table public.rooms
    drop constraint if exists rooms_searchable_name_length_limit;

alter table public.rooms
    add constraint rooms_searchable_name_length_limit
    check (char_length(btrim(searchable_name)) between 1 and 16)
    not valid;
