import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const workflowPath = path.join(root, '.github', 'workflows', 'backup-ranktiger-prod.yml');
const certificatePath = path.join(root, '.github', 'backup-keys', 'ranktiger-prod-backup-recovery.crt');
const encryptPath = path.join(root, 'scripts', 'encrypt-ranktiger-backup.mjs');
const decryptPath = path.join(root, 'scripts', 'decrypt-ranktiger-backup.mjs');
const guidePath = path.join(root, 'docs', 'RANKTIGER_PROD_ENCRYPTED_BACKUP.md');
const lockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_PATCH5_2.json');
const packagePath = path.join(root, 'package.json');
const expectedFingerprint = '92d5c109c6e94200b4390e5ce9710cc61a99a9da3d30ce651ca4baf8f3d34d18';

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function requireFile(filePath) {
  if (!fs.existsSync(filePath)) fail(`Missing required backup-safety file: ${path.relative(root, filePath)}`);
}

for (const required of [workflowPath, certificatePath, encryptPath, decryptPath, guidePath, lockPath, packagePath]) {
  requireFile(required);
}
if (process.exitCode) process.exit();

const workflow = fs.readFileSync(workflowPath, 'utf8');
const certificatePem = fs.readFileSync(certificatePath, 'utf8');
const encrypt = fs.readFileSync(encryptPath, 'utf8');
const decrypt = fs.readFileSync(decryptPath, 'utf8');
const guide = fs.readFileSync(guidePath, 'utf8');
const locked = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));

const requiredWorkflowFragments = [
  'BACKUP_RANKTIGER_PROD',
  'refs/heads/main',
  'group: ranktiger-prod-database-deploy',
  'SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}',
  'SUPABASE_DB_PASSWORD: ${{ secrets.RANKTIGER_SUPABASE_DB_PASSWORD }}',
  'RANKTIGER_SUPABASE_PROJECT_ID: ${{ secrets.RANKTIGER_SUPABASE_PROJECT_ID }}',
  'RANKTIGER_SUPABASE_URL: ${{ secrets.RANKTIGER_SUPABASE_URL }}',
  'stejewkuikvqpqotjnnt',
  'https://${RANKTIGER_SUPABASE_PROJECT_ID}.supabase.co',
  'supabase/setup-cli@v2',
  'version: 2.111.0',
  'supabase migration list --linked',
  'docs/LOCKED_MIGRATION_CHECKSUMS_PATCH5_2.json',
  'match(/\d{14}/)?.[0]',
  'remote.size !== 20',
  'supabase db dump --linked --file "$PLAIN_DIR/roles.sql" --role-only',
  'supabase db dump --linked --file "$PLAIN_DIR/schema.sql"',
  'supabase db dump --linked --file "$PLAIN_DIR/data.sql" --use-copy --data-only',
  '-x "storage.buckets_vectors" -x "storage.vector_indexes"',
  'supabase db dump --linked --file "$PLAIN_DIR/migration-history-schema.sql" --schema supabase_migrations',
  'supabase db dump --linked --file "$PLAIN_DIR/migration-history-data.sql" --use-copy --data-only --schema supabase_migrations',
  'node scripts/encrypt-ranktiger-backup.mjs',
  '--certificate .github/backup-keys/ranktiger-prod-backup-recovery.crt',
  'Remove plaintext before artifact upload',
  'actions/upload-artifact@v4',
  'path: ${{ runner.temp }}/ranktiger-prod-backup/encrypted/',
  'if-no-files-found: error',
  'retention-days: 1',
  'if: always()',
];
for (const fragment of requiredWorkflowFragments) {
  if (!workflow.includes(fragment)) fail(`Backup workflow is missing required safety fragment: ${fragment}`);
}
if (/^      BACKUP_ROOT:/m.test(workflow)) {
  fail('runner.temp cannot be referenced from job-level env; BACKUP_ROOT must be step-scoped.');
}
if ((workflow.match(/BACKUP_ROOT: \$\{\{ runner\.temp \}\}\/ranktiger-prod-backup/g) || []).length !== 5) {
  fail('Exactly five plaintext/encryption/cleanup steps must receive the guarded runner temp path.');
}

const forbiddenWorkflowPatterns = [
  /supabase\s+db\s+(push|reset|pull)/i,
  /supabase\s+migration\s+(repair|up|down|new)/i,
  /--include-seed|supabase\/seed\.sql/i,
  /git\s+push|github_update_ref/i,
  /wrangler|cloudflare\/pages-action|pages\s+deploy/i,
  /RANKTIGER_SUPABASE_SECRET|SERVICE_ROLE|sb_secret_/i,
  /BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY/i,
  /ranktiger-prod-backup-private\.pem/i,
];
for (const pattern of forbiddenWorkflowPatterns) {
  if (pattern.test(workflow)) fail(`Backup workflow contains forbidden write/secret pattern: ${pattern}`);
}

const encryptIndex = workflow.indexOf('name: Encrypt backup before artifact creation');
const removeIndex = workflow.indexOf('name: Remove plaintext before artifact upload');
const uploadIndex = workflow.indexOf('name: Upload encrypted backup artifact only');
if (!(encryptIndex >= 0 && encryptIndex < removeIndex && removeIndex < uploadIndex)) {
  fail('Workflow must encrypt, remove plaintext, and only then upload the artifact.');
}

if (locked.migration_count !== 20 || Object.keys(locked.migrations || {}).length !== 20) {
  fail('Pre-promotion backup lock must remain the immutable 20-migration Patch 5.2 baseline.');
}

try {
  const certificate = new crypto.X509Certificate(certificatePem);
  const fingerprint = certificate.fingerprint256.replaceAll(':', '').toLowerCase();
  if (fingerprint !== expectedFingerprint) fail('Recovery certificate fingerprint changed unexpectedly.');
  if (certificate.publicKey.asymmetricKeyType !== 'rsa') fail('Recovery certificate must use RSA.');
  if ((certificate.publicKey.asymmetricKeyDetails?.modulusLength || 0) < 4096) fail('Recovery RSA key must be at least 4096 bits.');
  if (certificate.ca) fail('Recovery certificate must be an end-entity encryption certificate, not a CA certificate.');
  if (Date.parse(certificate.validTo) < Date.parse('2035-01-01T00:00:00Z')) fail('Recovery certificate expires too soon.');
} catch (error) {
  fail(`Recovery certificate cannot be validated: ${error instanceof Error ? error.message : String(error)}`);
}

for (const [label, source, fragments] of [
  ['encryptor', encrypt, ['aes-256-gcm', 'randomBytes(32)', 'randomBytes(12)', 'RSA_PKCS1_OAEP_PADDING', "oaepHash: 'sha256'", 'getAuthTag()', 'certificate.fingerprint256']],
  ['decryptor', decrypt, ['aes-256-gcm', 'RSA_PKCS1_OAEP_PADDING', "oaepHash: 'sha256'", 'setAuthTag(authTag)', 'ciphertext SHA-256 mismatch', 'private recovery key does not match']],
]) {
  for (const fragment of fragments) {
    if (!source.includes(fragment)) fail(`Backup ${label} is missing required authenticated-encryption fragment: ${fragment}`);
  }
}

if (!guide.includes(expectedFingerprint.match(/.{2}/g).join(':').toUpperCase())) {
  fail('Recovery guide does not record the approved certificate fingerprint.');
}
if (!guide.includes('Storage object bytes') || !guide.includes('one day')) {
  fail('Recovery guide must state the storage-object limitation and artifact retention.');
}

if (pkg.scripts?.['verify:ranktiger-backup'] !== 'node scripts/verify-ranktiger-prod-backup.mjs') {
  fail('package.json is missing verify:ranktiger-backup.');
}
if (!pkg.scripts?.['verify:patch6']?.includes('npm run verify:ranktiger-backup')) {
  fail('The complete release verifier chain must include the backup-safety verifier.');
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (['.git', 'node_modules', 'dist'].includes(entry.name)) return [];
    const fullPath = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(fullPath) : [fullPath];
  });
}
const privateKeyMarker = ['-----BEGIN ', 'PRIVATE KEY-----'].join('');
for (const filePath of walk(root)) {
  const body = fs.readFileSync(filePath);
  if (body.includes(Buffer.from(privateKeyMarker))) {
    fail(`Private recovery key material is present in repository file: ${path.relative(root, filePath)}`);
  }
}

if (process.exitCode) process.exit();
console.log('PASS: RankTiger PROD backup workflow is manual, main-only, target-guarded, and read-only.');
console.log('PASS: exact 20-migration pre-promotion baseline is required before export.');
console.log('PASS: roles, schema, data, and migration history exports use the pinned Supabase CLI.');
console.log('PASS: AES-256-GCM and RSA-4096 OAEP-SHA256 protect the artifact before upload.');
console.log('PASS: repository contains the recovery certificate only; no private recovery key material.');
