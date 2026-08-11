import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };

let pkg;
let lock;
try {
  pkg = JSON.parse(await readFile(resolve(ROOT, 'package.json'), 'utf8'));
} catch (error) {
  console.error(`FAIL: Could not read package.json: ${error.message}`);
  process.exit(1);
}

try {
  lock = JSON.parse(await readFile(resolve(ROOT, 'package-lock.json'), 'utf8'));
} catch (error) {
  console.error('DEPENDENCY LOCK VERIFICATION FAILED');
  console.error('- package-lock.json is missing or unreadable.');
  process.exit(1);
}

pass(Number(lock.lockfileVersion) >= 3, 'package-lock.json must use lockfileVersion 3 or newer.');
pass(lock.name === pkg.name, 'package-lock.json name must match package.json.');
pass(lock.version === pkg.version, 'package-lock.json version must match package.json.');

const root = lock.packages?.[''];
pass(Boolean(root), 'package-lock.json must contain the root package entry.');
if (root) {
  pass(root.name === pkg.name, 'Root lock package name must match package.json.');
  pass(root.version === pkg.version, 'Root lock package version must match package.json.');

  for (const [name, version] of Object.entries(pkg.dependencies || {})) {
    pass(root.dependencies?.[name] === version, `Locked root dependency ${name} must match package.json exactly (${version}).`);
    pass(Boolean(lock.packages?.[`node_modules/${name}`]), `Locked dependency tree is missing ${name}.`);
  }
  for (const [name, version] of Object.entries(pkg.devDependencies || {})) {
    pass(root.devDependencies?.[name] === version, `Locked root devDependency ${name} must match package.json exactly (${version}).`);
    pass(Boolean(lock.packages?.[`node_modules/${name}`]), `Locked dependency tree is missing devDependency ${name}.`);
  }
}

for (const [path, entry] of Object.entries(lock.packages || {})) {
  if (!path || !path.startsWith('node_modules/')) continue;
  const resolved = String(entry?.resolved || '');
  if (resolved) {
    pass(/^https:\/\/registry\.npmjs\.org\//.test(resolved), `Non-registry dependency source is forbidden in production lock: ${path} -> ${resolved}`);
    pass(Boolean(entry.integrity), `Registry dependency is missing integrity hash: ${path}`);
  }
}

if (problems.length) {
  console.error('DEPENDENCY LOCK VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: ScoreMore dependency lock is source-controlled and internally consistent.');
console.log(`lockfileVersion: ${lock.lockfileVersion}`);
console.log(`Locked package entries: ${Object.keys(lock.packages || {}).length}`);
