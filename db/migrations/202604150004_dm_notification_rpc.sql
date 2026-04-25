create or replace function public.create_dm_message_notification(
  target_conversation_id uuid,
  target_recipient_profile_id uuid,
  target_message_preview text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_profile_id uuid;
  v_notification_id uuid;
  v_normalized_preview text;
begin
  v_actor_profile_id := public.current_profile_id();

  if v_actor_profile_id is null then
    raise exception 'Current profile could not be resolved.';
  end if;

  if target_conversation_id is null then
    raise exception 'Conversation is required.';
  end if;

  if target_recipient_profile_id is null then
    raise exception 'Recipient profile is required.';
  end if;

  if target_recipient_profile_id = v_actor_profile_id then
    raise exception 'Recipient must be another profile.';
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = target_conversation_id
      and cp.profile_id = v_actor_profile_id
  ) then
    raise exception 'Actor is not a participant in this conversation.';
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = target_conversation_id
      and cp.profile_id = target_recipient_profile_id
  ) then
    raise exception 'Recipient is not a participant in this conversation.';
  end if;

  v_normalized_preview := nullif(btrim(target_message_preview), '');

  insert into public.notifications (
    type,
    recipient_profile_id,
    actor_profile_id,
    conversation_id,
    message_preview,
    is_read
  )
  values (
    'dm_message',
    target_recipient_profile_id,
    v_actor_profile_id,
    target_conversation_id,
    v_normalized_preview,
    false
  )
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;

revoke all on function public.create_dm_message_notification(uuid, uuid, text) from public;
grant execute on function public.create_dm_message_notification(uuid, uuid, text) to authenticated;
