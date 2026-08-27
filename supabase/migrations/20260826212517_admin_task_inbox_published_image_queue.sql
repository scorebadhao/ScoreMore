begin;

-- A single server-owned summary keeps Admin Task Inbox counts and exact-record
-- routing independent of whichever paginated queue the browser has loaded.
create or replace function public.get_admin_task_inbox()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  with active_drafts as materialized (
    select
      d.*,
      jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) as source_image_count,
      exists (
        select 1
        from public.question_image_repairs r
        where r.draft_id = d.draft_id
          and r.status = 'PENDING'
      ) as has_pending_image
    from public.draft_questions d
    where d.question_status = 'DRAFT'
      and d.published_question_id is null
      and d.review_status not in ('REJECTED', 'PUBLISHED')
  ), draft_repairs as materialized (
    select
      d.*,
      case
        when d.content_repair_status = 'NEEDS_REPAIR' then 'CONTENT_REPAIR'
        when d.has_pending_image then 'PENDING'
        else 'IMAGE_REPAIR'
      end as task_status
    from active_drafts d
    where d.content_repair_status = 'NEEDS_REPAIR'
       or (
         d.source_image_count > 0
         and (
           d.has_pending_image
           or d.student_image_review_status not in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED')
         )
       )
  ), publish_ready as materialized (
    select d.*
    from active_drafts d
    where d.review_status = 'IN_REVIEW'
      and d.verification_status = 'VERIFIED'
      and d.reviewed_repair_revision = d.repair_revision
      and d.content_repair_status = 'READY'
      and d.content_source_confirmed_revision = d.repair_revision
      and d.correct_answer is not null
      and d.answer_source is not null
      and d.answer_source <> 'AI_PROPOSED'
      and nullif(btrim(d.explanation), '') is not null
      and nullif(btrim(d.question_text), '') is not null
      and coalesce(jsonb_typeof(d.options), '') = 'object'
      and d.options ?& array['A','B','C','D']
      and not exists (
        select 1 from jsonb_each_text(d.options) o where btrim(o.value) = ''
      )
      and coalesce(d.source_quality::text, 'CLEAR') <> 'UNREADABLE'
      and (
        (d.source_image_count = 0 and d.student_image_review_status = 'NOT_APPLICABLE')
        or
        (d.source_image_count > 0 and d.student_image_review_status in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED'))
      )
      and not d.has_pending_image
      and public.draft_student_image_ready(d.draft_id)
      and (
        d.source_option_anomaly <> 'DUPLICATE_OPTIONS_PRINTED'
        or nullif(btrim(d.source_option_anomaly_note), '') is not null
      )
      and (
        d.question_type <> 'PYQ'
        or (d.topic_id is not null and d.topic_resolution_status in ('MATCHED', 'ADMIN_CONFIRMED'))
      )
  ), final_reviews as materialized (
    select d.*
    from active_drafts d
    where d.content_repair_status = 'READY'
      and (
        (d.source_image_count = 0 and d.student_image_review_status = 'NOT_APPLICABLE')
        or
        (d.source_image_count > 0 and d.student_image_review_status in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED'))
      )
      and not d.has_pending_image
      and not exists (
        select 1 from publish_ready p where p.draft_id = d.draft_id
      )
  ), published_image_state as materialized (
    select
      q.*,
      exists (
        select 1
        from public.question_image_repairs r
        where r.question_id = q.question_id
          and r.status = 'PENDING'
      ) as has_pending_image,
      public.question_student_image_readiness(q.question_id) as image_readiness
    from public.questions q
    where q.question_status = 'PUBLISHED'
      and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0
  ), published_image_safety as materialized (
    select q.*
    from published_image_state q
    where q.has_pending_image
       or q.image_readiness not in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED')
  ), task_counts as (
    select
      (select count(*) from draft_repairs) as draft_repairs,
      (select count(*) from published_image_safety) as published_image_safety,
      (select count(*) from final_reviews) as final_reviews,
      (select count(*) from publish_ready) as ready_to_publish
  )
  select jsonb_build_object(
    'generated_at', current_timestamp,
    'recommended_bucket', case
      when c.draft_repairs > 0 then 'DRAFT_REPAIR'
      when c.published_image_safety > 0 then 'PUBLISHED_IMAGE_SAFETY'
      when c.final_reviews > 0 then 'FINAL_REVIEW'
      when c.ready_to_publish > 0 then 'PUBLISH'
      else null
    end,
    'draft_repairs', jsonb_build_object(
      'count', c.draft_repairs,
      'next', (
        select jsonb_build_object(
          'draft_id', d.draft_id,
          'display_id', d.proposed_question_id,
          'task_status', d.task_status,
          'reason_code', d.content_repair_reason_code
        )
        from draft_repairs d
        order by
          case d.task_status when 'CONTENT_REPAIR' then 1 when 'PENDING' then 2 else 3 end,
          d.updated_at,
          d.created_at,
          d.draft_id
        limit 1
      )
    ),
    'published_image_safety', jsonb_build_object(
      'count', c.published_image_safety,
      'next', (
        select jsonb_build_object(
          'question_id', q.question_id,
          'display_id', q.question_id,
          'task_status', case when q.has_pending_image then 'PENDING' else 'NEEDS_REPAIR' end
        )
        from published_image_safety q
        order by
          case when q.has_pending_image then 1 else 2 end,
          q.exam_date nulls last,
          q.shift_no nulls last,
          q.original_question_no nulls last,
          q.question_id
        limit 1
      )
    ),
    'final_reviews', jsonb_build_object(
      'count', c.final_reviews,
      'next', (
        select jsonb_build_object(
          'draft_id', d.draft_id,
          'display_id', d.proposed_question_id,
          'repair_revision', d.repair_revision
        )
        from final_reviews d
        order by d.created_at, d.draft_id
        limit 1
      )
    ),
    'ready_to_publish', jsonb_build_object(
      'count', c.ready_to_publish,
      'next', (
        select jsonb_build_object(
          'draft_id', d.draft_id,
          'display_id', d.proposed_question_id,
          'repair_revision', d.repair_revision
        )
        from publish_ready d
        order by d.reviewed_at nulls last, d.created_at, d.draft_id
        limit 1
      )
    )
  ) into v_result
  from task_counts c;

  return v_result;
end;
$$;

revoke all on function public.get_admin_task_inbox() from public, anon, authenticated;
grant execute on function public.get_admin_task_inbox() to authenticated;

comment on function public.get_admin_task_inbox() is
  'Admin-only read model with exact workflow counts and exact next-record identifiers for Task Inbox routing.';

commit;
