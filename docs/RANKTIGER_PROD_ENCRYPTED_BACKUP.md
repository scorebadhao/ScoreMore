# RankTiger PROD encrypted logical backup

## Purpose and boundary

`Backup RankTiger PROD Database — READ ONLY` creates the required pre-promotion rollback point for the RankTiger production database. The workflow is manually dispatched from ScoreMore `main` and accepts only the exact confirmation `BACKUP_RANKTIGER_PROD`.

The workflow reads RankTiger PROD, verifies the exact 20-migration pre-promotion baseline, creates the logical exports recommended by Supabase, encrypts them, deletes plaintext working files, and uploads only ciphertext. It never runs migrations or seed data, updates either GitHub repository, deploys a frontend, or invokes Cloudflare.

Official references:

- [Supabase backup and restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
- [Supabase CLI `db dump` reference](https://supabase.com/docs/reference/cli/supabase-db-dump)

## Backup contents

The encrypted payload contains:

- `roles.sql` — database roles
- `schema.sql` — application schema
- `data.sql` — data, including Supabase-managed Auth and Storage metadata supported by the CLI data export
- `migration-history-schema.sql` and `migration-history-data.sql` — the Supabase migration ledger
- `backup-manifest.json`, `checksums.sha256`, and this recovery guide

The backup does **not** contain Storage object bytes, Vault secrets, Edge Function source, or project-level Auth configuration. Git and release artifacts remain the recovery source for the frontend and Edge Function source. Storage object bytes require a separate object backup when production begins using them materially.

## Security model

- Payload encryption: AES-256-GCM with a fresh random key and IV for every run
- Key wrapping: RSA-4096 OAEP with SHA-256
- Recovery certificate SHA-256 fingerprint: `92:D5:C1:09:C6:E9:42:00:B4:39:0E:5C:E9:71:0C:C6:1A:99:A9:DA:3D:30:CE:65:1C:A4:BA:F8:F3:D3:4D:18`
- Private recovery key: stored separately; never committed or uploaded with the backup
- GitHub artifact retention: one day

Download the artifact promptly and store it separately from the recovery kit. Anyone holding both can recover sensitive database data, including authentication records.

## Decrypt and verify

Unzip the GitHub Actions artifact. From a machine with Node.js 22 or later, run:

```bash
node decrypt-ranktiger-backup.mjs \
  --input ranktiger-prod-backup.enc \
  --manifest encryption-manifest.json \
  --private-key ranktiger-prod-backup-private.pem \
  --certificate ranktiger-prod-backup-recovery.crt \
  --output ranktiger-prod-logical-backup.tar.gz

mkdir ranktiger-prod-logical-backup
tar -xzf ranktiger-prod-logical-backup.tar.gz -C ranktiger-prod-logical-backup
cd ranktiger-prod-logical-backup
sha256sum -c checksums.sha256
```

The decryption script verifies the ciphertext checksum, certificate fingerprint, key-pair match, AES-GCM authentication tag, and approved algorithm suite before writing plaintext.

## Restore boundary

Do not restore directly over live RankTiger PROD as an improvised rollback. Create an isolated recovery project, review the target extensions and platform configuration, and use the current Supabase recovery guidance. A typical reviewed restore uses the new project's connection string:

```bash
psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file roles.sql \
  --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql \
  --dbname "$RECOVERY_DATABASE_URL"
```

Restore the migration-history files only after checking the destination history and planned migration state. Re-enable required extensions, Realtime publications, Auth configuration, Edge Functions, and Storage object bytes separately. Every production restore requires a specific reviewed recovery plan and a new explicit authorization.
