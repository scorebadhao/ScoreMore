#!/usr/bin/env node

import {
  X509Certificate,
  constants,
  createCipheriv,
  createHash,
  publicEncrypt,
  randomBytes,
} from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const FORMAT = 'ranktiger-prod-logical-backup-encryption-v1';
const AAD = Buffer.from('RankTiger PROD encrypted logical backup v1', 'utf8');

function fail(message) {
  console.error(`Backup encryption failed: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!flag?.startsWith('--') || !value) fail(`invalid argument near ${flag || '(end)'}`);
    args[flag.slice(2)] = value;
  }
  return args;
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

const args = parseArgs(process.argv.slice(2));
for (const required of ['input', 'certificate', 'ciphertext', 'manifest']) {
  if (!args[required]) fail(`missing --${required}`);
}

try {
  const [plaintext, certificatePem] = await Promise.all([
    readFile(args.input),
    readFile(args.certificate, 'utf8'),
  ]);
  const certificate = new X509Certificate(certificatePem);
  const aesKey = randomBytes(32);
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', aesKey, iv, { authTagLength: 16 });
  cipher.setAAD(AAD);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const authTag = cipher.getAuthTag();
  const wrappedKey = publicEncrypt({
    key: certificate.publicKey,
    padding: constants.RSA_PKCS1_OAEP_PADDING,
    oaepHash: 'sha256',
  }, aesKey);

  const manifest = {
    format: FORMAT,
    created_at_utc: new Date().toISOString(),
    source_commit: process.env.GITHUB_SHA || null,
    payload_name: path.basename(args.input),
    cipher: 'AES-256-GCM',
    key_wrap: 'RSA-OAEP-SHA256',
    certificate_sha256_fingerprint: certificate.fingerprint256.replaceAll(':', '').toLowerCase(),
    aad_base64: AAD.toString('base64'),
    iv_base64: iv.toString('base64'),
    auth_tag_base64: authTag.toString('base64'),
    wrapped_key_base64: wrappedKey.toString('base64'),
    ciphertext_sha256: sha256(ciphertext),
    ciphertext_bytes: ciphertext.length,
  };

  await writeFile(args.ciphertext, ciphertext, { mode: 0o600 });
  await writeFile(args.manifest, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });
  console.log(`Encrypted ${plaintext.length} payload bytes into ${ciphertext.length} authenticated ciphertext bytes.`);
  console.log(`Recovery certificate SHA-256 fingerprint: ${certificate.fingerprint256}`);
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
