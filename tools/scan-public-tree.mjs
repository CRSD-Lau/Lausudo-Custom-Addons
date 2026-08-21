import crypto from 'node:crypto';
import childProcess from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const rootArgument = process.argv.indexOf('--root');
if (rootArgument >= 0 && !process.argv[rootArgument + 1]) throw new Error('Missing value for --root.');
const root = rootArgument >= 0 ? path.resolve(process.argv[rootArgument + 1]) : path.resolve(here, '..');
const excludedRoots = new Set(['.git', 'dist', 'node_modules', 'coverage', 'TestResults', '.private-staging']);
const deniedSegments = new Set([
  'wtf', 'data', 'account', 'accounts', 'savedvariables', 'backup', 'backups',
  'cache', 'logs', 'errors', 'screenshots', 'crashes', 'dumps', 'codexbackups',
]);
const deniedExtensions = new Set([
  '.mpq', '.disabled', '.exe', '.dll', '.dmp', '.log', '.wtf', '.bak', '.old', '.tmp',
  '.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.addon32', '.addon64',
]);
const mediaExtensions = new Set(['.ttf', '.otf', '.tga', '.blp', '.png', '.jpg', '.jpeg', '.gif', '.wav', '.mp3', '.ogg']);
const textExtensions = new Set(['.md', '.txt', '.json', '.yml', '.yaml', '.lua', '.toc', '.xml', '.ps1', '.psm1', '.psd1', '.mjs', '.js', '.py', '.csv', '.gitignore', '.gitattributes', '.editorconfig']);
const maxBytes = 100 * 1024 * 1024;
const errors = [];
const files = [];

function toPosix(value) {
  return value.split(path.sep).join('/');
}

function manifestRelative(value, label) {
  if (typeof value !== 'string' || !value) {
    errors.push(`${label} must be a non-empty relative path.`);
    return null;
  }
  const normalized = value.replaceAll('\\', '/').replace(/\/$/, '');
  const segments = normalized.split('/');
  if (path.posix.isAbsolute(normalized) || path.win32.isAbsolute(value) || /^[A-Za-z]:/.test(normalized)
      || segments.some((segment) => !segment || segment === '.' || segment === '..' || /[:*?"<>|\0]/.test(segment) || /[. ]$/.test(segment))) {
    errors.push(`${label} is not a safe relative path: ${value}`);
    return null;
  }
  return normalized.toLowerCase();
}

function walk(directory, relative = '') {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (!relative && excludedRoots.has(entry.name)) continue;
    const childRelative = relative ? path.join(relative, entry.name) : entry.name;
    const full = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      errors.push(`Symbolic links and reparse-like entries are not allowed: ${toPosix(childRelative)}`);
    } else if (entry.isDirectory()) {
      walk(full, childRelative);
    } else if (entry.isFile()) {
      files.push({ full, relative: childRelative });
    }
  }
}

if (fs.lstatSync(root).isSymbolicLink()) throw new Error('The scan root cannot be a symbolic link or reparse-like entry.');
walk(root);

if (fs.existsSync(path.join(root, '.git'))) {
  const tracked = childProcess.execFileSync('git', ['-C', root, 'ls-files', '-z'], { encoding: 'utf8' }).split('\0').filter(Boolean);
  for (const trackedPath of tracked) {
    const top = trackedPath.replaceAll('\\', '/').split('/')[0];
    if (excludedRoots.has(top)) errors.push(`Tracked content is hidden under an excluded development root: ${trackedPath}`);
  }
}

const provenance = JSON.parse(fs.readFileSync(path.join(root, 'manifests', 'media-provenance.json'), 'utf8'));
const suite = JSON.parse(fs.readFileSync(path.join(root, 'manifests', 'suite.json'), 'utf8'));
const bundledMappings = [];
for (const component of suite.components.filter((entry) => entry.distribution === 'bundled')) {
  const source = manifestRelative(component.source?.path, `${component.id} bundled source`);
  const destination = manifestRelative(component.destination, `${component.id} destination`);
  if (source && destination) bundledMappings.push({ source, destination });
}

function releaseEquivalent(value) {
  const normalized = value.toLowerCase().replaceAll('\\', '/').replace(/\/$/, '');
  const mapping = bundledMappings.find(({ source }) => normalized === source || normalized.startsWith(`${source}/`));
  if (!mapping) return normalized;
  return `${mapping.destination}${normalized.slice(mapping.source.length)}`;
}

const allowedMediaRoots = provenance.allowedRoots.flatMap((entry) => {
  const source = manifestRelative(entry.path, `Media provenance root ${entry.path}`);
  if (!source) return [];
  return [...new Set([source, releaseEquivalent(source)])];
});
const waReview = JSON.parse(fs.readFileSync(path.join(root, 'manifests', 'wa-code-review.json'), 'utf8'));
const reviewedWa = new Map();
for (const entry of waReview.reviewedFiles) {
  const source = manifestRelative(entry.path, `WeakAuras review path ${entry.path}`);
  if (!source) continue;
  reviewedWa.set(source, entry);
  reviewedWa.set(releaseEquivalent(source), entry);
}

for (const file of files) {
  const relative = toPosix(file.relative);
  const lower = relative.toLowerCase();
  const segments = lower.split('/');
  const extension = path.extname(file.full).toLowerCase();
  const stat = fs.statSync(file.full);

  if (segments.some((segment) => deniedSegments.has(segment))) {
    errors.push(`Denied client/private path segment: ${relative}`);
  }
  if (deniedExtensions.has(extension)) {
    errors.push(`Denied artifact type ${extension}: ${relative}`);
  }
  if (stat.size > maxBytes) {
    errors.push(`File exceeds the 100 MiB repository limit: ${relative}`);
  }

  if (mediaExtensions.has(extension)) {
    const covered = allowedMediaRoots.some((allowed) => lower === allowed || lower.startsWith(`${allowed}/`));
    if (!covered) errors.push(`Binary/media file lacks an approved provenance root: ${relative}`);
  }

  const isWeakAuraCode = lower.startsWith('packages/weakauras/') || lower.startsWith('interface/addons/lausudovisualcore/');
  if (isWeakAuraCode && extension === '.lua') {
    const review = reviewedWa.get(lower);
    if (!review || review.status !== 'approved') {
      errors.push(`WeakAuras Lua requires an approved code-review record: ${relative}`);
    } else {
      const hash = crypto.createHash('sha256').update(fs.readFileSync(file.full)).digest('hex');
      if (hash !== review.sha256) errors.push(`WeakAuras review hash is stale: ${relative}`);
    }
  }

  const textLike = textExtensions.has(extension) || ['license', 'readme', '.gitignore', '.gitattributes', '.editorconfig'].includes(path.basename(file.full).toLowerCase());
  if (textLike && stat.size <= 5 * 1024 * 1024) {
    const text = fs.readFileSync(file.full, 'utf8');
    const localPath = /(?:^|[\s"'(=])(?:[A-Za-z]:[\\/]|\\\\[^\\\s]+\\)/im;
    const credentialAssignment = /\b(?:password|passwd|token|api[_-]?key|client[_-]?secret)\s*[=:]\s*["'][^"']{4,}["']/i;
    const privateConfigPath = /WTF[\\/]Account[\\/][^<>*?"|\r\n]+[\\/]SavedVariables/i;
    const playerRealmMapping = /UnitName\s*\(\s*["']player["']\s*\)[\s\S]{0,240}GetRealmName\s*\(/i;
    const persistedIdentityMap = /(?:\b(?:profileKeys|characterProfiles|realmProfiles|accountProfiles)\b|["'](?:profileKeys|characterProfiles|realmProfiles|accountProfiles)["']\s*\])\s*[=:]\s*\{[\s\S]{0,500}\[\s*["'][^"']+["']\s*\]\s*=/i;
    const persistedHistory = /\b(?:chatHistory|combatHistory|whisperHistory|channelHistory)\b\s*[=:]/i;
    const structuralExempt = lower === 'tools/scan-public-tree.mjs' || lower === 'tools/export-visual-profile.mjs';
    if (localPath.test(text)) errors.push(`Absolute local machine path found: ${relative}`);
    if (credentialAssignment.test(text)) errors.push(`Credential-like assignment found: ${relative}`);
    if (privateConfigPath.test(text)) errors.push(`Concrete private configuration path found: ${relative}`);
    if (!structuralExempt && playerRealmMapping.test(text)) errors.push(`Player-to-realm identity mapping logic found: ${relative}`);
    if (!structuralExempt && persistedIdentityMap.test(text)) errors.push(`Persisted account/realm/profile mapping found: ${relative}`);
    if (!structuralExempt && persistedHistory.test(text)) errors.push(`Persisted chat/combat history field found: ${relative}`);
  }
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Privacy/provenance scan passed for ${files.length} public-tree files.`);
}
