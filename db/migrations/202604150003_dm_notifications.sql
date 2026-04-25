alter table public.notifications
  add column if not exists conversation_id uuid references public.conversations(id) on delete cascade,
  add column if not exists message_preview text;

create index if not exists notifications_conversation_id_idx
  on public.notifications(conversation_id);
