create or replace function public.home_feed_cards(p_limit integer default 12)
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
  ),
  base as (
    select
      p.id as post_id,
      fs.id as spot_id,
      p.caption,
      p.created_at,
      author.id as author_id,
      author.display_name as author_name,
      author.avatar_url as author_avatar_url,
      fs.name as spot_name,
      fs.latitude as spot_lat,
      fs.longitude as spot_lng,
      photo.storage_path as thumbnail_url
    from public.posts p
    join public.post_spots ps on ps.post_id = p.id
    join public.fishing_spots fs on fs.id = ps.fishing_spot_id
    join lateral (
      select pr.id, pr.display_name, pr.avatar_url
      from public.profiles pr
      where pr.auth_user_id = p.user_id
         or pr.id::text = p.user_id::text
      limit 1
    ) author on true
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
        exists (
          select 1
          from public.follows f, viewer v
          where f.follower_id = v.profile_id
            and f.following_id = author.id
        )
        or exists (
          select 1
          from viewer v
          where fs.owner_profile_id = v.profile_id
        )
      )
    order by p.created_at desc
    limit greatest(coalesce(p_limit, 12), 1)
  )
  select
    b.post_id,
    b.spot_id,
    b.caption,
    b.created_at,
    b.author_id,
    b.author_name,
    b.author_avatar_url,
    b.spot_name,
    b.spot_lat,
    b.spot_lng,
    b.thumbnail_url,
    coalesce((
      select count(*)
      from public.post_likes pl
      where pl.post_id = b.post_id
    ), 0) as like_count,
    coalesce((
      select count(*)
      from public.post_comments pc
      where pc.post_id = b.post_id
    ), 0) as comment_count,
    null::text as score_summary
  from base b
  order by b.created_at desc;
$$;

revoke all on function public.home_feed_cards(integer) from public;
grant execute on function public.home_feed_cards(integer) to authenticated;

create or replace function public.profile_summary(p_profile_id uuid default null)
returns table (
  profile_id uuid,
  display_name text,
  username text,
  avatar_url text,
  cover_url text,
  bio text,
  city text,
  home_region text,
  website_url text,
  instagram text,
  x_handle text,
  youtube text,
  tiktok text,
  post_count bigint,
  spot_count bigint,
  follower_count bigint,
  following_count bigint,
  is_own boolean,
  is_following boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select public.current_profile_id() as profile_id
  ),
  resolved as (
    select p.*
    from public.profiles p, viewer v
    where p.id = coalesce(p_profile_id, v.profile_id)
    limit 1
  )
  select
    r.id as profile_id,
    r.display_name,
    r.username,
    r.avatar_url,
    r.cover_url,
    r.bio,
    r.city,
    r.home_region,
    r.website_url,
    r.instagram,
    r.x_handle,
    r.youtube,
    r.tiktok,
    coalesce((
      select count(*)
      from public.posts p
      where p.user_id::text = coalesce(r.auth_user_id::text, r.id::text)
    ), 0) as post_count,
    coalesce((
      select count(*)
      from public.fishing_spots fs
      where fs.owner_profile_id = r.id
    ), 0) as spot_count,
    coalesce((
      select count(*)
      from public.follows f
      where f.following_id = r.id
    ), 0) as follower_count,
    coalesce((
      select count(*)
      from public.follows f
      where f.follower_id = r.id
    ), 0) as following_count,
    exists (
      select 1
      from viewer v
      where v.profile_id = r.id
    ) as is_own,
    exists (
      select 1
      from public.follows f, viewer v
      where f.follower_id = v.profile_id
        and f.following_id = r.id
    ) as is_following
  from resolved r;
$$;

revoke all on function public.profile_summary(uuid) from public;
grant execute on function public.profile_summary(uuid) to authenticated;

create or replace function public.profile_post_cards(
  p_profile_id uuid,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (
  post_id uuid,
  profile_id uuid,
  caption text,
  created_at timestamptz,
  thumbnail_url text,
  fishing_spot_id uuid,
  region text,
  latitude double precision,
  longitude double precision
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id as post_id,
    pr.id as profile_id,
    p.caption,
    p.created_at,
    photo.storage_path as thumbnail_url,
    ps.fishing_spot_id,
    ps.region,
    ps.latitude,
    ps.longitude
  from public.profiles pr
  join public.posts p
    on p.user_id::text = coalesce(pr.auth_user_id::text, pr.id::text)
  left join lateral (
    select s.fishing_spot_id, s.region, s.latitude, s.longitude
    from public.post_spots s
    where s.post_id = p.id
    order by s.id asc
    limit 1
  ) ps on true
  left join lateral (
    select pp.storage_path
    from public.post_photos pp
    where pp.post_id = p.id
    order by pp.id asc
    limit 1
  ) photo on true
  where pr.id = p_profile_id
  order by p.created_at desc
  limit greatest(coalesce(p_limit, 10), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.profile_post_cards(uuid, integer, integer) from public;
grant execute on function public.profile_post_cards(uuid, integer, integer) to authenticated;

create or replace function public.map_spot_cards(p_limit integer default 32)
returns table (
  spot_id uuid,
  name text,
  latitude double precision,
  longitude double precision,
  water_type text,
  score_value integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    fs.id as spot_id,
    fs.name,
    fs.latitude,
    fs.longitude,
    fs.water_type,
    null::integer as score_value
  from public.fishing_spots fs
  where fs.status = 'active'
    and fs.visibility = 'exact'
  order by fs.created_at desc
  limit greatest(coalesce(p_limit, 32), 1);
$$;

revoke all on function public.map_spot_cards(integer) from public;
grant execute on function public.map_spot_cards(integer) to authenticated;
