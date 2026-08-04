# ScoreMore Setup Guide

## 1. Create separate services

Create:

- GitHub repository: `ScoreMore`
- A new Supabase project used only by ScoreMore
- A separate ChatGPT project using the supplied ScoreMore source lock

Do not reuse ScoreBadhao environment values or Google Sheets.

## 2. Install local requirements

Use Node.js 22.12 or later.

```bash
npm install
```

Install or run the Supabase CLI using the official Supabase instructions.

## 3. Configure Supabase CLI

From the repository root:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --include-seed
```

After the first migration is applied, make every schema change through a new file in `supabase/migrations/`.

Do not make unmanaged production schema changes in the remote Table Editor or SQL Editor.

## 4. Configure frontend environment

Copy:

```bash
cp .env.example .env
```

Add:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_BROWSER_SAFE_PUBLISHABLE_OR_ANON_KEY
```

Never add the service-role key.

## 5. Run locally

```bash
npm run dev
```

Public page:

```text
http://localhost:5173/
```

Student page:

```text
http://localhost:5173/student.html
```

Admin page:

```text
http://localhost:5173/admin.html
```

## 6. Bootstrap the first owner/admin

1. Create the first account using the student sign-up form.
2. In the Supabase SQL Editor, run this one-time owner bootstrap with the real email:

```sql
update public.profiles
set role = 'ADMIN'
where email = 'OWNER_EMAIL@example.com';
```

3. Sign out and sign in through `admin.html`.

Authenticated students use `student.html`; signed-out access to that page redirects to `index.html`.

The browser cannot promote users to admin. This is intentional.

## 7. Verify security before content work

Test with a student account and an admin account.

Student account must be unable to:

- select from `questions`
- select from `draft_questions`
- upload to `source-documents`
- call `publish_draft_question`
- read another student's attempts or answers

Admin account must be able to:

- upload a private source file
- create a draft
- review drafts
- publish a valid reviewed draft

During an active attempt, the question response must not include `correct_answer` or `explanation`.

## 8. Create the first real test

After publishing real questions, insert a test through a migration or the Supabase dashboard during the early prototype stage, then capture the change as a migration before production.

Example filter:

```sql
insert into public.tests (
  test_id, board_id, exam_id, test_name, test_type, selection_mode,
  question_count, duration_minutes, marks_per_question, negative_marks,
  status, is_free, exam_year, exam_date, shift_no, paper_code,
  section_code, question_filter
) values (
  'GSSSB-CCE-2024-0401S1-FULL',
  'GSSSB',
  'CCE',
  'GSSSB CCE 01-04-2024 Shift 1 — Full PYQ',
  'PYQ_FULL',
  'FIXED_PAPER',
  100,
  60,
  1,
  0.25,
  'PUBLISHED',
  true,
  2024,
  '2024-04-01',
  1,
  '0401S1',
  'FULL',
  '{"question_type":"PYQ","board_id":"GSSSB","exam_id":"CCE","exam_year":2024,"exam_date":"2024-04-01","shift_no":1,"paper_code":"0401S1"}'::jsonb
);
```

## 9. GitHub Pages deployment

Add repository secrets:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Set **Settings → Pages → Source** to **GitHub Actions**.

Push to `main`. The included workflow builds and deploys `dist/`.

## 10. Production checklist

- Email confirmation and redirect URLs configured
- Site URL updated in Supabase Auth
- GitHub Pages URL added to Auth redirect URLs
- RLS tests passed
- No service-role key in repository history
- Source bucket private
- One real PYQ shift imported through drafts
- Full and sectional tests reuse the same master questions
- Mobile refresh and back navigation tested
- Offline answer queue tested
