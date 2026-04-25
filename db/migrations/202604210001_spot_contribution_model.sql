alter table public.posts
  add column if not exists contribution_type text not null default 'spot_contribution',
  add column if not exists result_status text,
  add column if not exists technique_tags text[] not null default '{}'::text[],
  add column if not exists bait_tags text[] not null default '{}'::text[],
  add column if not exists time_context_tags text[] not null default '{}'::text[];

create index if not exists idx_post_spots_fishing_spot_id
  on public.post_spots (fishing_spot_id);

create index if not exists idx_posts_result_status
  on public.posts (result_status);
