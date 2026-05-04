create or replace function public.home_feed_cards(p_limit integer default 10)
returns table (
  post_id uuid,
  spot_id uuid,
  caption text,
  created_at timestamptz,
  author_id uuid,
  author_name text,
  author_avatar_url text,
  spot_name text,
  spot_lat double precision,
  spot_lng double precision,
  thumbnail_url text,
  like_count bigint,
  comment_count bigint,
  score_summary text
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select public.current_profile_id() as profile_id
  )
  select
    p.id as post_id,
    fs.id as spot_id,
    p.caption,
    p.created_at,
    author.id as author_id,
    author.display_name as author_name,
    null::text as author_avatar_url,
    fs.name as spot_name,
    fs.latitude as spot_lat,
    fs.longitude as spot_lng,
    photo.storage_path as thumbnail_url,
    0::bigint as like_count,
    0::bigint as comment_count,
    null::text as score_summary
  from public.posts p
  join public.post_spots ps on ps.post_id = p.id
  join public.fishing_spots fs on fs.id = ps.fishing_spot_id
  join public.profiles author
    on author.auth_user_id = p.user_id
    or author.id::text = p.user_id::text
  left join lateral (
    select pp.storage_path
    from public.post_photos pp
    where pp.post_id = p.id
    order by pp.id asc
    limit 1
  ) photo on true
  where fs.status = 'active'
    and fs.visibility in ('exact', 'public')
    and (
      fs.owner_profile_id = (select profile_id from viewer)
      or exists (
        select 1
        from public.follows f
        where f.follower_id = (select profile_id from viewer)
          and f.following_id = author.id
      )
    )
  order by p.created_at desc
  limit greatest(coalesce(p_limit, 10), 1);
$$;

revoke all on function public.home_feed_cards(integer) from public;
grant execute on function public.home_feed_cards(integer) to authenticated;
