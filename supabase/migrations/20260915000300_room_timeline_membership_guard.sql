-- 룸 타임라인의 멤버십 가드를 좁힌다.
--
-- 20260915000100이 타임라인을 룸 전체로 넓히면서, 가드에 남아 있던 폴백이 유출 경로가 됐다.
-- 가드는 room_members에 없더라도 "이 룸에 예전 메시지나 채팅이 하나라도 있으면" 통과시킨다.
-- 타임라인이 자기 행만 돌려줄 때는 무해했지만, 이제는 룸을 떠난 사람이 전원의
-- sender_nickname/video_url/created_at을 포함한 전체 타임라인을 받게 된다.
-- (스토리지는 살아있는 room_members 행을 요구하므로 영상 자체는 여전히 404다 —
--  새는 건 메타데이터다.)
--
-- 폴백 자체는 유지한다. 없애면 룸을 떠난 사람이 자기가 주고받은 기록까지 못 보게 된다.
-- 대신 룸 전체를 보는 것은 실제 멤버로 한정한다.

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
    is_member boolean;
begin
    if me is null then raise exception 'auth required'; end if;

    is_member := exists (
        select 1 from public.room_members rm where rm.room_id = room_uuid and rm.user_id = me
    );

    -- 폴백(예전 메시지/채팅 기록만 있는 호출자)은 접근 자체는 계속 허용하되,
    -- 아래에서 자기 행만 보게 제한한다. 룸 전체를 반환하게 된 뒤로는 이 폴백을
    -- 그대로 두면 탈퇴한 사람이 전원의 메타데이터를 읽는다.
    if not is_member and not exists (
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
          -- 룸 멤버만 룸 전체를 본다. 멤버가 아니면 예전처럼 자기가 주고받은 것만.
          and (is_member or m.receiver_uid = me or m.sender_uid = me)
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
