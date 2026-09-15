-- 룸 타임라인을 "나에게 오간 것"에서 "이 룸에서 오간 것"으로 넓힌다.
--
-- 원본 핑은 수신자 수만큼 행이 생기지만(팬아웃) 자동 얼굴 회신은 원 발신자 1명에게만
-- 생긴다. 그래서 A의 핑에 B와 C가 회신하면 A는 셋 다 보지만 B는 A·B만, C는 A·C만 봤다.
-- 회신자끼리 서로의 회신을 볼 수 없었던 것이 원인이다.
--
-- 전송 방식은 건드리지 않는다. 회신을 전원에게 팬아웃하면 B가 C의 회신으로 알림과
-- 자동재생까지 받게 되어 동작이 바뀐다. 여기서는 보이는 범위만 넓힌다.
-- 읽기 권한은 이미 룸 멤버 단위로 열려 있다(20260523000500_storage_read_room_member).

drop function if exists public.ping_room_messages(uuid, timestamptz, int);

create or replace function public.ping_room_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns table (
    id uuid,
    room_id uuid,
    sender_uid uuid,
    receiver_uid uuid,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz,
    capture_mode text,
    aspect_ratio real,
    hidden_for_receiver boolean,
    allows_local_save boolean,
    is_auto_reply boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members rm where rm.room_id = room_uuid and rm.user_id = me
    ) and not exists (
        select 1 from public.messages mm where mm.room_id = room_uuid and (mm.sender_uid = me or mm.receiver_uid = me)
    ) and not exists (
        select 1 from public.chat_messages cm where cm.room_id = room_uuid and cm.sender_uid = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    with visible_messages as (
        select m.*
        from public.messages m
        where m.room_id = room_uuid
          -- 내가 숨긴 영상은 어느 행이 살아남든 나에게 보이면 안 된다. 팬아웃된 핑은
          -- 수신자마다 행이 따로 있어서, 내 행만 걸러내면 남의 행이 dedup을 통과해
          -- 숨김이 무력화된다. 그래서 행이 아니라 영상 단위로 제외한다.
          and not exists (
              select 1
              from public.messages h
              where h.room_id = m.room_id
                and h.video_url = m.video_url
                and h.receiver_uid = me
                and h.hidden_for_receiver = true
          )
    ),
    ranked_messages as (
        select
            m.*,
            row_number() over (
                partition by m.room_id, m.video_url
                -- 내가 수신한 행을 반드시 먼저 남긴다. HistoryViewModel의
                -- videoIdsToMarkRead가 receiver_uid = 나 로 알림 정리 대상을 고르기
                -- 때문에, 남의 행이 살아남으면 룸을 열어도 알림이 지워지지 않는다.
                order by (m.receiver_uid = me) desc, m.created_at asc, m.id asc
            ) as video_rank
        from visible_messages m
    )
    select
        m.id,
        m.room_id,
        m.sender_uid,
        m.receiver_uid,
        m.sender_nickname,
        m.video_id,
        m.video_url,
        m.duration_ms,
        jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio) as mirror_position,
        m.status,
        m.created_at,
        m.expires_at,
        m.capture_mode,
        m.aspect_ratio,
        m.hidden_for_receiver,
        m.allows_local_save,
        m.is_auto_reply
    from ranked_messages m
    where m.video_rank = 1
      and (before_ts is null or m.created_at < before_ts)
    order by m.created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_messages(uuid, timestamptz, int) to authenticated;
