-- ScoreMore / RankTiger auth foundation:
-- permit first-party Google OAuth students while preserving database-owned roles,
-- then require a one-time mobile + learning-preferences onboarding RPC.

begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := lower(coalesce(nullif(btrim(new.raw_app_meta_data ->> 'provider'), ''), 'email'));
  v_mobile text := nullif(btrim(new.raw_user_meta_data ->> 'mobile'), '');
  v_name text := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    'Student'
  );
begin
  if v_mobile is not null and v_mobile !~ '^\+91[6-9][0-9]{9}$' then
    raise exception 'A valid Indian mobile number is required for registration.';
  end if;

  if v_provider <> 'google' and v_mobile is null then
    raise exception 'A valid Indian mobile number is required for registration.';
  end if;

  if v_provider not in ('email', 'google') then
    raise exception 'This sign-in provider is not approved.';
  end if;

  insert into public.profiles (user_id, email, full_name, mobile)
  values (new.id, new.email, v_name, v_mobile)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Admins who opt into a verified TOTP factor must present an AAL2 session.
-- Admins without a verified factor retain the current behavior until enrollment.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'ADMIN'
      and p.status = 'ACTIVE'
  )
  and (
    not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = (select auth.uid())
        and f.status = 'verified'
    )
    or coalesce((select auth.jwt() ->> 'aal'), 'aal1') = 'aal2'
  );
$$;

revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to authenticated;

comment on function public.is_admin() is
  'Database-owned active ADMIN check; a verified MFA factor makes AAL2 mandatory for that admin.';

create or replace function public.complete_student_onboarding(
  p_full_name text,
  p_mobile text,
  p_language text,
  p_target_board_id text,
  p_target_exam_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_full_name, ''));
  v_mobile text := btrim(coalesce(p_mobile, ''));
  v_language text := upper(btrim(coalesce(p_language, '')));
  v_board_id text := nullif(btrim(coalesce(p_target_board_id, '')), '');
  v_exam_id text := nullif(btrim(coalesce(p_target_exam_id, '')), '');
  v_exam_board text;
  v_existing_mobile text;
  v_role public.user_role;
  v_status public.entity_status;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 100 then raise exception 'Full name must contain 2 to 100 characters.' using errcode = 'P0001'; end if;
  if v_mobile !~ '^\+91[6-9][0-9]{9}$' then raise exception 'Enter a valid 10-digit Indian mobile number.' using errcode = 'P0001'; end if;
  if v_language !~ '^[A-Z][A-Z_-]{1,31}$' then raise exception 'Choose a valid preferred language.' using errcode = 'P0001'; end if;
  if v_board_id is null then raise exception 'Choose your target board.' using errcode = 'P0001'; end if;
  if v_exam_id is null then raise exception 'Choose your target exam.' using errcode = 'P0001'; end if;

  select p.mobile, p.role, p.status
  into v_existing_mobile, v_role, v_status
  from public.profiles p
  where p.user_id = v_user_id
  for update;

  if not found then raise exception 'Student profile not found.' using errcode = 'P0001'; end if;
  if v_role <> 'STUDENT' or v_status <> 'ACTIVE' then raise exception 'Active student access is required.' using errcode = 'P0001'; end if;
  if v_existing_mobile is not null then raise exception 'Student onboarding is already complete.' using errcode = 'P0001'; end if;

  if not exists (select 1 from public.boards b where b.board_id = v_board_id and b.status = 'ACTIVE') then
    raise exception 'Selected board is unavailable.' using errcode = 'P0001';
  end if;

  select e.board_id into v_exam_board
  from public.exams e
  where e.exam_id = v_exam_id and e.status = 'ACTIVE';
  if v_exam_board is null then raise exception 'Selected exam is unavailable.' using errcode = 'P0001'; end if;
  if v_exam_board <> v_board_id then raise exception 'Selected exam does not belong to the selected board.' using errcode = 'P0001'; end if;

  update public.profiles
  set full_name = v_name,
      mobile = v_mobile,
      language = v_language,
      target_board_id = v_board_id,
      target_exam_id = v_exam_id,
      updated_at = now()
  where user_id = v_user_id and mobile is null;

  if not found then raise exception 'Student onboarding is already complete.' using errcode = 'P0001'; end if;
  return public.get_student_profile();
end;
$$;

revoke all on function public.complete_student_onboarding(text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.complete_student_onboarding(text,text,text,text,text) to authenticated;

comment on function public.complete_student_onboarding(text,text,text,text,text) is
  'One-time completion of missing Google OAuth student profile fields for auth.uid(); role and authorization remain database-owned.';

commit;
