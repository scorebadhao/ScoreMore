#!/usr/bin/env node

import {
  X509Certificate,
  constants,
  createDecipheriv,
  createHash,
  createPublicKey,
  privateDecrypt,
  timingSafeEqual,
} from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const FORMAT = 'ranktiger-prod-logical-backup-encryption-v1';

function fail(message) {
  console.error(`Backup decryption failed: ${message}`);
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

function decodeBase64(value, label) {
  if (typeof value !== 'string' || !value.length) fail(`manifest is missing ${label}`);
  return Buffer.from(value, 'base64');
}

const args = parseArgs(process.argv.slice(2));
for (const required of ['input', 'manifest', 'private-key', 'certificate', 'output']) {
  if (!args[required]) fail(`missing --${required}`);
}

try {
  const [ciphertext, manifestText, privateKeyPem, certificatePem] = await Promise.all([
    readFile(args.input),
    readFile(args.manifest, 'utf8'),
    readFile(args['private-key'], 'utf8'),
    readFile(args.certificate, 'utf8'),
  ]);
  const manifest = JSON.parse(manifestText);
  if (manifest.format !== FORMAT) fail(`unsupported manifest format: ${manifest.format || '(missing)'}`);
  if (manifest.cipher !== 'AES-256-GCM' || manifest.key_wrap !== 'RSA-OAEP-SHA256') {
    fail('manifest algorithms are not the approved encryption suite');
  }
  if (sha256(ciphertext) !== manifest.ciphertext_sha256) fail('ciphertext SHA-256 mismatch');

  const certificate = new X509Certificate(certificatePem);
  const fingerprint = certificate.fingerprint256.replaceAll(':', '').toLowerCase();
  if (fingerprint !== manifest.certificate_sha256_fingerprint) fail('recovery certificate fingerprint mismatch');

  const certPublic = certificate.publicKey.export({ type: 'spki', format: 'der' });
  const privatePublic = createPublicKey(privateKeyPem).export({ type: 'spki', format: 'der' });
  if (certPublic.length !== privatePublic.length || !timingSafeEqual(certPublic, privatePublic)) {
    fail('private recovery key does not match the recovery certificate');
  }

  const aesKey = privateDecrypt({
    key: privateKeyPem,
    padding: constants.RSA_PKCS1_OAEP_PADDING,
    oaepHash: 'sha256',
  }, decodeBase64(manifest.wrapped_key_base64, 'wrapped_key_base64'));
  if (aesKey.length !== 32) fail('unwrapped AES key length is invalid');

  const iv = decodeBase64(manifest.iv_base64, 'iv_base64');
  const authTag = decodeBase64(manifest.auth_tag_base64, 'auth_tag_base64');
  const aad = decodeBase64(manifest.aad_base64, 'aad_base64');
  const decipher = createDecipheriv('aes-256-gcm', aesKey, iv, { authTagLength: 16 });
  decipher.setAAD(aad);
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  await writeFile(args.output, plaintext, { mode: 0o600 });
  console.log(`Authenticated decryption succeeded: ${plaintext.length} payload bytes written.`);
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
