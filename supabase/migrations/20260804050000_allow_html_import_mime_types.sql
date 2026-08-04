-- ScoreMore Phase 3B hotfix
-- Allow versioned HTML import packages in the existing private source-documents bucket.
-- This preserves all currently allowed PDF/image MIME types.

do $$
begin
  if not exists (
    select 1
    from storage.buckets
    where id = 'source-documents'
  ) then
    raise exception 'ScoreMore source-documents storage bucket does not exist';
  end if;
end;
$$;

update storage.buckets
set allowed_mime_types = (
  select array_agg(distinct mime order by mime)
  from unnest(
    coalesce(allowed_mime_types, '{}'::text[])
    || array['text/html', 'application/xhtml+xml']::text[]
  ) as allowed(mime)
)
where id = 'source-documents';

do $$
declare
  v_allowed text[];
begin
  select allowed_mime_types
  into v_allowed
  from storage.buckets
  where id = 'source-documents';

  if not ('text/html' = any(v_allowed)) then
    raise exception 'text/html was not added to source-documents allowed MIME types';
  end if;

  if not ('application/xhtml+xml' = any(v_allowed)) then
    raise exception 'application/xhtml+xml was not added to source-documents allowed MIME types';
  end if;
end;
$$;
