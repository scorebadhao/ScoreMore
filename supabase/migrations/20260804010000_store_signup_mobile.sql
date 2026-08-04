-- ScoreMore: store a normalized mobile number from Auth signup metadata.
-- The profiles.mobile column already exists in the initial schema.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_mobile text;
begin
  normalized_mobile := nullif(btrim(new.raw_user_meta_data ->> 'mobile'), '');

  if normalized_mobile is null or normalized_mobile !~ '^\+91[6-9][0-9]{9}$' then
    raise exception 'A valid Indian mobile number is required for ScoreMore registration.';
  end if;

  insert into public.profiles (user_id, email, full_name, mobile)
  values (
    new.id,
    new.email,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), 'Student'),
    normalized_mobile
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public;
