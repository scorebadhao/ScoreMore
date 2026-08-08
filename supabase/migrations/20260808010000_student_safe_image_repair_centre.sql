begin;

-- ScoreMore Student-safe Image Repair Centre.
--
-- Raw source captures remain in questions.image_refs and the private
-- source-documents bucket. Only an explicitly approved, diagram-only crop is
-- copied into questions.student_image_refs for protected attempt delivery.

create table public.question_image_repairs (
  repair_id uuid primary key default gen_random_uuid(),
  question_id text not null references public.questions(question_id) on delete cascade,
  storage_bucket text not null default 'student-question-images',
  storage_path text not null,
  original_file_name text not null,
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes > 0 and file_size_bytes <= 5242880),
  checksum_sha256 text not null check (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  pixel_width integer check (pixel_width is null or pixel_width between 1 and 8000),
  pixel_height integer check (pixel_height is null or pixel_height between 1 and 8000),
  alt_text text not null,
  admin_note text,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'SUPERSEDED', 'REMOVED')),
  uploaded_by uuid not null references public.profiles(user_id),
  approved_by uuid references public.profiles(user_id),
  approved_at timestamptz,
  removed_by uuid references public.profiles(user_id),
  removed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (storage_bucket, storage_path)
);

create unique index question_image_repairs_one_pending_idx
  on public.question_image_repairs(question_id)
  where status = 'PENDING';

create unique index question_image_repairs_one_approved_idx
  on public.question_image_repairs(question_id)
  where status = 'APPROVED';

create index question_image_repairs_queue_idx
  on public.question_image_repairs(status, created_at desc);

create trigger question_image_repairs_set_updated_at
before update on public.question_image_repairs
for each row execute function public.set_updated_at();

alter table public.question_image_repairs enable row level security;
revoke all on public.question_image_repairs from anon, authenticated;

comment on table public.question_image_repairs is
  'Audited admin workflow for pending and approved student-safe diagram crops. Direct browser table access is denied; admin RPCs own every state transition.';

-- Approved crops are private objects. Admins manage them; an authenticated
-- student may read only an approved object referenced by one of their attempt
-- questions. Storage still returns a short-lived signed URL, never a raw source
-- capture or a permanently public asset.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'student-question-images',
  'student-question-images',
  false,
  5242880,
  array['image/png','image/jpeg','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_read_student_question_image(p_storage_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (select public.is_admin())
    or exists (
      select 1
      from public.question_image_repairs r
      join public.attempt_questions aq
        on aq.question_id = r.question_id
      join public.attempts a
        on a.attempt_id = aq.attempt_id
      where r.storage_bucket = 'student-question-images'
        and r.storage_path = p_storage_path
        and r.status = 'APPROVED'
        and a.user_id = (select auth.uid())
    );
$$;

revoke all on function public.can_read_student_question_image(text) from public, anon, authenticated;
grant execute on function public.can_read_student_question_image(text) to authenticated;

create policy student_question_images_authenticated_select
on storage.objects for select to authenticated
using (
  bucket_id = 'student-question-images'
  and (select public.can_read_student_question_image(name))
);

create policy student_question_images_admin_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'student-question-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select public.is_admin())
);

create policy student_question_images_admin_update
on storage.objects for update to authenticated
using (
  bucket_id = 'student-question-images'
  and (select public.is_admin())
)
with check (
  bucket_id = 'student-question-images'
  and (select public.is_admin())
);

create policy student_question_images_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'student-question-images'
  and (select public.is_admin())
);

-- Lightweight queue. Source images are deliberately excluded here; one
-- question's raw source is returned only when an admin opens its detail view.
create or replace function public.list_student_image_repair_queue(
  p_status text default 'NEEDS_REPAIR',
  p_search text default null,
  p_paper_code text default null,
  p_shift_no integer default null,
  p_section_code text default null,
  p_original_question_no integer default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := upper(coalesce(nullif(trim(p_status), ''), 'NEEDS_REPAIR'));
  v_items jsonb;
  v_summary jsonb;
  v_total bigint;
begin
  if not (select public.is_admin()) then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  if v_status not in ('NEEDS_REPAIR', 'PENDING', 'APPROVED', 'ALL') then
    raise exception 'Invalid image-repair status filter.' using errcode = 'P0001';
  end if;

  with base as (
    select
      q.question_id,
      q.question_text,
      q.question_type,
      q.exam_year,
      q.exam_date,
      q.shift_no,
      q.paper_code,
      q.original_question_no,
      q.section_code,
      q.subject_id,
      s.subject_name,
      jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id,
      approved.repair_id as approved_repair_id,
      approved.approved_at,
      case
        when pending.repair_id is not null then 'PENDING'
        when approved.repair_id is not null
          or jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) > 0 then 'APPROVED'
        else 'NEEDS_REPAIR'
      end as repair_status
    from public.questions q
    join public.subjects s on s.subject_id = q.subject_id
    left join lateral (
      select r.repair_id
      from public.question_image_repairs r
      where r.question_id = q.question_id and r.status = 'PENDING'
      order by r.created_at desc
      limit 1
    ) pending on true
    left join lateral (
      select r.repair_id, r.approved_at
      from public.question_image_repairs r
      where r.question_id = q.question_id and r.status = 'APPROVED'
      order by r.approved_at desc nulls last
      limit 1
    ) approved on true
    where q.question_status = 'PUBLISHED'
      and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0
      and (
        nullif(trim(coalesce(p_search, '')), '') is null
        or q.question_id ilike '%' || trim(p_search) || '%'
        or q.question_text ilike '%' || trim(p_search) || '%'
      )
      and (nullif(trim(coalesce(p_paper_code, '')), '') is null or q.paper_code = upper(trim(p_paper_code)))
      and (p_shift_no is null or q.shift_no = p_shift_no)
      and (nullif(trim(coalesce(p_section_code, '')), '') is null or q.section_code = upper(trim(p_section_code)))
      and (p_original_question_no is null or q.original_question_no = p_original_question_no)
  )
  select jsonb_build_object(
    'total_candidates', count(*),
    'needs_repair', count(*) filter (where repair_status = 'NEEDS_REPAIR'),
    'pending', count(*) filter (where repair_status = 'PENDING'),
    'approved', count(*) filter (where repair_status = 'APPROVED')
  )
  into v_summary
  from base;

  with base as (
    select
      q.question_id,
      q.question_text,
      q.question_type,
      q.exam_year,
      q.exam_date,
      q.shift_no,
      q.paper_code,
      q.original_question_no,
      q.section_code,
      q.subject_id,
      s.subject_name,
      jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id,
      approved.repair_id as approved_repair_id,
      approved.approved_at,
      case
        when pending.repair_id is not null then 'PENDING'
        when approved.repair_id is not null
          or jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) > 0 then 'APPROVED'
        else 'NEEDS_REPAIR'
      end as repair_status
    from public.questions q
    join public.subjects s on s.subject_id = q.subject_id
    left join lateral (
      select r.repair_id
      from public.question_image_repairs r
      where r.question_id = q.question_id and r.status = 'PENDING'
      order by r.created_at desc
      limit 1
    ) pending on true
    left join lateral (
      select r.repair_id, r.approved_at
      from public.question_image_repairs r
      where r.question_id = q.question_id and r.status = 'APPROVED'
      order by r.approved_at desc nulls last
      limit 1
    ) approved on true
    where q.question_status = 'PUBLISHED'
      and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0
      and (
        nullif(trim(coalesce(p_search, '')), '') is null
        or q.question_id ilike '%' || trim(p_search) || '%'
        or q.question_text ilike '%' || trim(p_search) || '%'
      )
      and (nullif(trim(coalesce(p_paper_code, '')), '') is null or q.paper_code = upper(trim(p_paper_code)))
      and (p_shift_no is null or q.shift_no = p_shift_no)
      and (nullif(trim(coalesce(p_section_code, '')), '') is null or q.section_code = upper(trim(p_section_code)))
      and (p_original_question_no is null or q.original_question_no = p_original_question_no)
  ), filtered as (
    select *
    from base
    where v_status = 'ALL' or repair_status = v_status
  )
  select count(*) into v_total from filtered;

  with base as (
    select
      q.question_id,
      q.question_text,
      q.question_type,
      q.exam_year,
      q.exam_date,
      q.shift_no,
      q.paper_code,
      q.original_question_no,
      q.section_code,
      q.subject_id,
      s.subject_name,
      jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id,
      approved.repair_id as approved_repair_id,
      approved.approved_at,
      case
        when pending.repair_id is not null then 'PENDING'
        when approved.repair_id is not null
          or jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) > 0 then 'APPROVED'
        else 'NEEDS_REPAIR'
      end as repair_status
    from public.questions q
    join public.subjects s on s.subject_id = q.subject_id
    left join lateral (
      select r.repair_id
      from public.question_image_repairs r
      where r.question_id = q.question_id and r.status = 'PENDING'
      order by r.created_at desc
      limit 1
    ) pending on true
    left join lateral (
      select r.repair_id, r.approved_at
      from public.question_image_repairs r
      where r.question_id = q.question_id and r.status = 'APPROVED'
      order by r.approved_at desc nulls last
      limit 1
    ) approved on true
    where q.question_status = 'PUBLISHED'
      and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0
      and (
        nullif(trim(coalesce(p_search, '')), '') is null
        or q.question_id ilike '%' || trim(p_search) || '%'
        or q.question_text ilike '%' || trim(p_search) || '%'
      )
      and (nullif(trim(coalesce(p_paper_code, '')), '') is null or q.paper_code = upper(trim(p_paper_code)))
      and (p_shift_no is null or q.shift_no = p_shift_no)
      and (nullif(trim(coalesce(p_section_code, '')), '') is null or q.section_code = upper(trim(p_section_code)))
      and (p_original_question_no is null or q.original_question_no = p_original_question_no)
  ), filtered as (
    select *
    from base
    where v_status = 'ALL' or repair_status = v_status
    order by
      case repair_status when 'NEEDS_REPAIR' then 1 when 'PENDING' then 2 else 3 end,
      exam_date desc nulls last,
      shift_no nulls last,
      original_question_no nulls last,
      question_id
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 20), 1), 100)
  )
  select coalesce(jsonb_agg(
    to_jsonb(filtered)
    order by
      case repair_status when 'NEEDS_REPAIR' then 1 when 'PENDING' then 2 else 3 end,
      exam_date desc nulls last,
      shift_no nulls last,
      original_question_no nulls last,
      question_id
  ), '[]'::jsonb)
  into v_items
  from filtered;

  return jsonb_build_object(
    'summary', coalesce(v_summary, '{}'::jsonb),
    'total', coalesce(v_total, 0),
    'limit', least(greatest(coalesce(p_limit, 20), 1), 100),
    'offset', greatest(coalesce(p_offset, 0), 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_student_image_repair_detail(p_question_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not (select public.is_admin()) then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'question', jsonb_build_object(
      'question_id', q.question_id,
      'question_type', q.question_type,
      'question_text', q.question_text,
      'options', q.options,
      'exam_year', q.exam_year,
      'exam_date', q.exam_date,
      'shift_no', q.shift_no,
      'paper_code', q.paper_code,
      'original_question_no', q.original_question_no,
      'section_code', q.section_code,
      'subject_id', q.subject_id,
      'subject_name', s.subject_name,
      'source_page', q.source_page,
      'image_refs', q.image_refs,
      'student_image_refs', q.student_image_refs
    ),
    'repairs', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'repair_id', r.repair_id,
          'status', r.status,
          'storage_bucket', r.storage_bucket,
          'storage_path', r.storage_path,
          'original_file_name', r.original_file_name,
          'mime_type', r.mime_type,
          'file_size_bytes', r.file_size_bytes,
          'checksum_sha256', r.checksum_sha256,
          'pixel_width', r.pixel_width,
          'pixel_height', r.pixel_height,
          'alt_text', r.alt_text,
          'admin_note', r.admin_note,
          'uploaded_by', r.uploaded_by,
          'approved_by', r.approved_by,
          'approved_at', r.approved_at,
          'removed_by', r.removed_by,
          'removed_at', r.removed_at,
          'created_at', r.created_at,
          'updated_at', r.updated_at
        ) order by r.created_at desc
      )
      from public.question_image_repairs r
      where r.question_id = q.question_id
    ), '[]'::jsonb)
  )
  into v_result
  from public.questions q
  join public.subjects s on s.subject_id = q.subject_id
  where q.question_id = upper(trim(p_question_id))
    and q.question_status = 'PUBLISHED';

  if v_result is null then
    raise exception 'Published question not found.' using errcode = 'P0001';
  end if;

  return v_result;
end;
$$;

create or replace function public.register_student_image_upload(
  p_question_id text,
  p_storage_path text,
  p_original_file_name text,
  p_mime_type text,
  p_file_size_bytes bigint,
  p_checksum_sha256 text,
  p_pixel_width integer default null,
  p_pixel_height integer default null,
  p_alt_text text default 'Question diagram',
  p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_question_id text := upper(trim(p_question_id));
  v_previous_pending public.question_image_repairs%rowtype;
  v_new public.question_image_repairs%rowtype;
begin
  if v_admin is null or not (select public.is_admin()) then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  if p_mime_type not in ('image/png', 'image/jpeg', 'image/webp') then
    raise exception 'Only PNG, JPEG and WebP crops are allowed.' using errcode = 'P0001';
  end if;
  if p_file_size_bytes is null or p_file_size_bytes <= 0 or p_file_size_bytes > 5242880 then
    raise exception 'Student image must be between 1 byte and 5 MB.' using errcode = 'P0001';
  end if;
  if lower(trim(coalesce(p_checksum_sha256, ''))) !~ '^[0-9a-f]{64}$' then
    raise exception 'A valid SHA-256 checksum is required.' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_alt_text, '')), '') is null then
    raise exception 'Student image alt text is required.' using errcode = 'P0001';
  end if;
  if p_pixel_width is not null and (p_pixel_width < 1 or p_pixel_width > 8000) then
    raise exception 'Image width is outside the allowed range.' using errcode = 'P0001';
  end if;
  if p_pixel_height is not null and (p_pixel_height < 1 or p_pixel_height > 8000) then
    raise exception 'Image height is outside the allowed range.' using errcode = 'P0001';
  end if;

  perform 1
  from public.questions q
  where q.question_id = v_question_id
    and q.question_status = 'PUBLISHED'
  for update;
  if not found then
    raise exception 'Published question not found.' using errcode = 'P0001';
  end if;

  if p_storage_path not like v_admin::text || '/' || v_question_id || '/%' then
    raise exception 'Storage path does not match this admin and question.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'student-question-images'
      and o.name = p_storage_path
  ) then
    raise exception 'Uploaded student image object was not found.' using errcode = 'P0001';
  end if;

  select * into v_previous_pending
  from public.question_image_repairs r
  where r.question_id = v_question_id and r.status = 'PENDING'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous_pending.repair_id;
  end if;

  insert into public.question_image_repairs (
    question_id, storage_bucket, storage_path, original_file_name, mime_type,
    file_size_bytes, checksum_sha256, pixel_width, pixel_height, alt_text,
    admin_note, status, uploaded_by
  ) values (
    v_question_id, 'student-question-images', p_storage_path, trim(p_original_file_name), p_mime_type,
    p_file_size_bytes, lower(trim(p_checksum_sha256)), p_pixel_width, p_pixel_height, trim(p_alt_text),
    nullif(trim(coalesce(p_admin_note, '')), ''), 'PENDING', v_admin
  )
  returning * into v_new;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'REGISTER_STUDENT_IMAGE',
    'QUESTION_IMAGE_REPAIR',
    v_new.repair_id::text,
    jsonb_build_object(
      'question_id', v_question_id,
      'storage_path', p_storage_path,
      'checksum_sha256', lower(trim(p_checksum_sha256)),
      'superseded_pending_repair_id', v_previous_pending.repair_id
    )
  );

  return jsonb_build_object(
    'repair_id', v_new.repair_id,
    'question_id', v_new.question_id,
    'status', v_new.status,
    'storage_bucket', v_new.storage_bucket,
    'storage_path', v_new.storage_path,
    'superseded_storage_path', v_previous_pending.storage_path
  );
end;
$$;

create or replace function public.approve_student_image_repair(
  p_repair_id uuid,
  p_alt_text text,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_repair public.question_image_repairs%rowtype;
  v_previous public.question_image_repairs%rowtype;
begin
  if v_admin is null or not (select public.is_admin()) then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if p_confirmation <> 'APPROVE_STUDENT_IMAGE' then
    raise exception 'Image approval confirmation is required.' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_alt_text, '')), '') is null then
    raise exception 'Student image alt text is required.' using errcode = 'P0001';
  end if;

  select * into v_repair
  from public.question_image_repairs
  where repair_id = p_repair_id
  for update;
  if not found or v_repair.status <> 'PENDING' then
    raise exception 'Pending student image was not found.' using errcode = 'P0001';
  end if;

  perform 1
  from public.questions q
  where q.question_id = v_repair.question_id
    and q.question_status = 'PUBLISHED'
  for update;
  if not found then
    raise exception 'Published question not found.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = v_repair.storage_bucket
      and o.name = v_repair.storage_path
  ) then
    raise exception 'Pending student image object is missing.' using errcode = 'P0001';
  end if;

  select * into v_previous
  from public.question_image_repairs r
  where r.question_id = v_repair.question_id and r.status = 'APPROVED'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous.repair_id;
  end if;

  update public.question_image_repairs
  set status = 'APPROVED',
      alt_text = trim(p_alt_text),
      admin_note = nullif(trim(coalesce(p_admin_note, '')), ''),
      approved_by = v_admin,
      approved_at = now(),
      removed_by = null,
      removed_at = null
  where repair_id = p_repair_id
  returning * into v_repair;

  update public.questions
  set student_image_refs = jsonb_build_array(jsonb_build_object(
    'repair_id', v_repair.repair_id,
    'bucket', v_repair.storage_bucket,
    'path', v_repair.storage_path,
    'alt', v_repair.alt_text,
    'mime_type', v_repair.mime_type,
    'checksum_sha256', v_repair.checksum_sha256,
    'approved_at', v_repair.approved_at
  ))
  where question_id = v_repair.question_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    case when v_previous.repair_id is null then 'APPROVE_STUDENT_IMAGE' else 'REPLACE_STUDENT_IMAGE' end,
    'QUESTION',
    v_repair.question_id,
    jsonb_build_object(
      'repair_id', v_repair.repair_id,
      'storage_path', v_repair.storage_path,
      'replaced_repair_id', v_previous.repair_id,
      'replaced_storage_path', v_previous.storage_path,
      'admin_note', nullif(trim(coalesce(p_admin_note, '')), '')
    )
  );

  return jsonb_build_object(
    'question_id', v_repair.question_id,
    'repair_id', v_repair.repair_id,
    'status', v_repair.status,
    'approved_at', v_repair.approved_at,
    'replaced_storage_path', v_previous.storage_path
  );
end;
$$;

create or replace function public.discard_student_image_upload(
  p_repair_id uuid,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_repair public.question_image_repairs%rowtype;
begin
  if v_admin is null or not (select public.is_admin()) then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if p_confirmation <> 'DISCARD_STUDENT_IMAGE' then
    raise exception 'Discard confirmation is required.' using errcode = 'P0001';
  end if;

  select * into v_repair
  from public.question_image_repairs
  where repair_id = p_repair_id
  for update;
  if not found or v_repair.status <> 'PENDING' then
    raise exception 'Pending student image was not found.' using errcode = 'P0001';
  end if;

  update public.question_image_repairs
  set status = 'REMOVED',
      admin_note = coalesce(nullif(trim(coalesce(p_admin_note, '')), ''), admin_note),
      removed_by = v_admin,
      removed_at = now()
  where repair_id = p_repair_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'DISCARD_STUDENT_IMAGE',
    'QUESTION_IMAGE_REPAIR',
    p_repair_id::text,
    jsonb_build_object('question_id', v_repair.question_id, 'storage_path', v_repair.storage_path, 'admin_note', p_admin_note)
  );

  return jsonb_build_object(
    'question_id', v_repair.question_id,
    'repair_id', v_repair.repair_id,
    'status', 'REMOVED',
    'storage_path', v_repair.storage_path
  );
end;
$$;

create or replace function public.remove_approved_student_image(
  p_question_id text,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_question public.questions%rowtype;
  v_repair public.question_image_repairs%rowtype;
begin
  if v_admin is null or not (select public.is_admin()) then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if p_confirmation <> 'REMOVE_STUDENT_IMAGE' then
    raise exception 'Removal confirmation is required.' using errcode = 'P0001';
  end if;

  select * into v_question
  from public.questions
  where question_id = upper(trim(p_question_id))
    and question_status = 'PUBLISHED'
  for update;
  if not found then
    raise exception 'Published question not found.' using errcode = 'P0001';
  end if;

  select * into v_repair
  from public.question_image_repairs
  where question_id = v_question.question_id and status = 'APPROVED'
  for update;

  if v_repair.repair_id is null and jsonb_array_length(coalesce(v_question.student_image_refs, '[]'::jsonb)) = 0 then
    raise exception 'This question has no approved student image.' using errcode = 'P0001';
  end if;

  if v_repair.repair_id is not null then
    update public.question_image_repairs
    set status = 'REMOVED',
        admin_note = coalesce(nullif(trim(coalesce(p_admin_note, '')), ''), admin_note),
        removed_by = v_admin,
        removed_at = now()
    where repair_id = v_repair.repair_id;
  end if;

  update public.questions
  set student_image_refs = '[]'::jsonb
  where question_id = v_question.question_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'REMOVE_STUDENT_IMAGE',
    'QUESTION',
    v_question.question_id,
    jsonb_build_object(
      'repair_id', v_repair.repair_id,
      'storage_path', v_repair.storage_path,
      'admin_note', nullif(trim(coalesce(p_admin_note, '')), '')
    )
  );

  return jsonb_build_object(
    'question_id', v_question.question_id,
    'repair_id', v_repair.repair_id,
    'status', 'REMOVED',
    'storage_path', v_repair.storage_path
  );
end;
$$;

revoke all on function public.list_student_image_repair_queue(text, text, text, integer, text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.get_student_image_repair_detail(text) from public, anon, authenticated;
revoke all on function public.register_student_image_upload(text, text, text, text, bigint, text, integer, integer, text, text) from public, anon, authenticated;
revoke all on function public.approve_student_image_repair(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.discard_student_image_upload(uuid, text, text) from public, anon, authenticated;
revoke all on function public.remove_approved_student_image(text, text, text) from public, anon, authenticated;

grant execute on function public.list_student_image_repair_queue(text, text, text, integer, text, integer, integer, integer) to authenticated;
grant execute on function public.get_student_image_repair_detail(text) to authenticated;
grant execute on function public.register_student_image_upload(text, text, text, text, bigint, text, integer, integer, text, text) to authenticated;
grant execute on function public.approve_student_image_repair(uuid, text, text, text) to authenticated;
grant execute on function public.discard_student_image_upload(uuid, text, text) to authenticated;
grant execute on function public.remove_approved_student_image(text, text, text) to authenticated;

comment on function public.list_student_image_repair_queue(text, text, text, integer, text, integer, integer, integer) is
  'Admin-only lightweight queue of published visual questions and their student-safe crop state.';

comment on function public.approve_student_image_repair(uuid, text, text, text) is
  'Admin-only audited approval that atomically replaces questions.student_image_refs with one verified private crop.';

commit;
