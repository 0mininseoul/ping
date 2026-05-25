-- v0.3.27: image attachments for room chat.

alter table public.chat_messages
    add column if not exists media_path text,
    add column if not exists media_mime_type text,
    add column if not exists media_width int,
    add column if not exists media_height int,
    add column if not exists media_file_name text;

alter table public.chat_messages
    drop constraint if exists chat_messages_body_check;

alter table public.chat_messages
    drop constraint if exists chat_messages_body_or_media_check;

alter table public.chat_messages
    add constraint chat_messages_body_or_media_check
    check (
        char_length(body) <= 2000
        and (
            char_length(body) > 0
            or media_path is not null
        )
    );

alter table public.chat_messages
    drop constraint if exists chat_messages_media_consistency_check;

alter table public.chat_messages
    add constraint chat_messages_media_consistency_check
    check (
        (
            media_path is null
            and media_mime_type is null
            and media_width is null
            and media_height is null
            and media_file_name is null
        )
        or (
            media_path is not null
            and media_mime_type in (
                'image/jpeg',
                'image/png',
                'image/heic',
                'image/heif',
                'image/gif',
                'image/webp'
            )
            and (media_width is null or media_width > 0)
            and (media_height is null or media_height > 0)
        )
    );

create index if not exists chat_messages_media_path_idx
    on public.chat_messages (media_path)
    where media_path is not null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ping-media', 'ping-media', false, 15728640, array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/gif', 'image/webp'])
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Ping media owner upload" on storage.objects;
create policy "Ping media owner upload"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'ping-media'
        and (storage.foldername(name))[1] = auth.uid()::text
        and (storage.foldername(name))[2] = 'chat-images'
    );

drop policy if exists "Ping media owner update" on storage.objects;
create policy "Ping media owner update"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'ping-media'
        and (storage.foldername(name))[1] = auth.uid()::text
        and (storage.foldername(name))[2] = 'chat-images'
    )
    with check (
        bucket_id = 'ping-media'
        and (storage.foldername(name))[1] = auth.uid()::text
        and (storage.foldername(name))[2] = 'chat-images'
    );

drop policy if exists "Ping media owner delete" on storage.objects;
create policy "Ping media owner delete"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'ping-media'
        and (storage.foldername(name))[1] = auth.uid()::text
        and (storage.foldername(name))[2] = 'chat-images'
    );

drop policy if exists "Ping media room member read" on storage.objects;
create policy "Ping media room member read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'ping-media'
        and (
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1
                from public.chat_messages cm
                join public.room_members rm on rm.room_id = cm.room_id
                where rm.user_id = auth.uid()
                  and cm.media_path = storage.objects.name
            )
        )
    );

drop function if exists public.ping_send_chat(uuid, text, uuid, uuid);

create or replace function public.ping_send_chat(
    room_uuid uuid,
    body_text text default '',
    reply_chat_uuid uuid default null,
    reply_video_uuid uuid default null,
    message_uuid uuid default null,
    media_path_text text default null,
    media_mime_type_text text default null,
    media_width_int int default null,
    media_height_int int default null,
    media_file_name_text text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    nickname_value text;
    new_id uuid := coalesce(message_uuid, gen_random_uuid());
    body_value text := coalesce(body_text, '');
    media_path_value text := nullif(media_path_text, '');
    media_mime_value text := nullif(media_mime_type_text, '');
begin
    if me is null then raise exception 'auth required'; end if;

    if reply_chat_uuid is not null and reply_video_uuid is not null then
        raise exception 'reply target must be at most one';
    end if;

    if char_length(body_value) > 2000
       or (char_length(body_value) = 0 and media_path_value is null) then
        raise exception 'invalid body length';
    end if;

    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) then
        raise exception 'not a member';
    end if;

    if reply_chat_uuid is not null and not exists (
        select 1 from public.chat_messages where id = reply_chat_uuid and room_id = room_uuid
    ) then
        raise exception 'reply chat not in this room';
    end if;

    if reply_video_uuid is not null and not exists (
        select 1 from public.messages where id = reply_video_uuid and room_id = room_uuid
    ) then
        raise exception 'reply video not in this room';
    end if;

    if media_path_value is not null then
        if media_mime_value not in (
            'image/jpeg',
            'image/png',
            'image/heic',
            'image/heif',
            'image/gif',
            'image/webp'
        ) then
            raise exception 'invalid media mime type';
        end if;

        if media_path_value not like (me::text || '/chat-images/%') then
            raise exception 'invalid media path';
        end if;

        if not exists (
            select 1 from storage.objects
            where bucket_id = 'ping-media'
              and name = media_path_value
        ) then
            raise exception 'media object missing';
        end if;
    end if;

    select profiles.nickname into nickname_value from public.profiles where id = me;
    if nickname_value is null then nickname_value := 'unknown'; end if;

    insert into public.chat_messages(
        id,
        room_id,
        sender_uid,
        sender_nickname,
        body,
        reply_to_chat_id,
        reply_to_video_id,
        media_path,
        media_mime_type,
        media_width,
        media_height,
        media_file_name
    )
    values (
        new_id,
        room_uuid,
        me,
        nickname_value,
        body_value,
        reply_chat_uuid,
        reply_video_uuid,
        media_path_value,
        media_mime_value,
        media_width_int,
        media_height_int,
        nullif(media_file_name_text, '')
    )
    returning id into new_id;

    return new_id;
end;
$$;

grant execute on function public.ping_send_chat(uuid, text, uuid, uuid, uuid, text, text, int, int, text) to authenticated;

create or replace function public.ping_delete_chat(chat_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner uuid;
    media_path_value text;
begin
    if me is null then raise exception 'auth required'; end if;

    select sender_uid, media_path
      into owner, media_path_value
      from public.chat_messages
     where id = chat_uuid;

    if owner is null then return; end if;
    if owner <> me then raise exception 'only sender can delete'; end if;

    if media_path_value is not null then
        delete from storage.objects
        where bucket_id = 'ping-media'
          and name = media_path_value;
    end if;

    delete from public.chat_messages where id = chat_uuid;
end;
$$;

grant execute on function public.ping_delete_chat(uuid) to authenticated;

create or replace function public.ping_cleanup_expired_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    msg_record record;
    chat_record record;
begin
    for msg_record in
        select m.id, m.video_url, m.sender_uid
        from public.messages m
        where m.created_at < now() - interval '30 days'
    loop
        delete from storage.objects
        where bucket_id = 'ping-videos' and name = msg_record.video_url;
        delete from public.messages where id = msg_record.id;
    end loop;

    for chat_record in
        select cm.id, cm.media_path
        from public.chat_messages cm
        where cm.created_at < now() - interval '30 days'
    loop
        if chat_record.media_path is not null then
            delete from storage.objects
            where bucket_id = 'ping-media' and name = chat_record.media_path;
        end if;
        delete from public.chat_messages where id = chat_record.id;
    end loop;

    delete from public.message_reactions
    where chat_message_id is null and video_message_id is null;

    delete from public.invitations where expires_at < now();
    delete from public.invite_links where expires_at < now();
end;
$$;
