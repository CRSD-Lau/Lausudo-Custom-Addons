import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const manifests = path.join(root, 'manifests');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);

function safeRelative(value, label) {
  if (typeof value !== 'string' || !value) throw new Error(`${label} must be a non-empty relative path.`);
  const normalized = value.replaceAll('\\', '/');
  if (path.posix.isAbsolute(normalized) || path.win32.isAbsolute(value) || /^[A-Za-z]:/.test(normalized)) {
    throw new Error(`${label} must not be absolute.`);
  }
  const segments = normalized.split('/');
  for (const segment of segments) {
    if (!segment || segment === '.' || segment === '..') throw new Error(`${label} contains a traversal or empty segment.`);
    if (/[:*?"<>|\0]/.test(segment) || /[. ]$/.test(segment)) throw new Error(`${label} contains an unsafe Windows path segment.`);
    const basename = segment.split('.')[0];
    if (/^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/i.test(basename)) throw new Error(`${label} contains a reserved Windows name.`);
  }
  return normalized;
}

function resolveInsideRoot(relative, label) {
  const normalized = safeRelative(relative, label);
  const full = path.resolve(root, ...normalized.split('/'));
  const fromRoot = path.relative(root, full);
  if (!fromRoot || fromRoot === '..' || fromRoot.startsWith(`..${path.sep}`) || path.isAbsolute(fromRoot)) {
    throw new Error(`${label} escapes or resolves to the repository root.`);
  }
  return full;
}

const pairs = [
  ['suite.schema.json', 'suite.json'],
  ['hd-patches.schema.json', 'hd-patches.json'],
  ['media-provenance.schema.json', 'media-provenance.json'],
  ['wa-code-review.schema.json', 'wa-code-review.json'],
];

for (const [schemaName, documentName] of pairs) {
  const schema = readJson(path.join(manifests, schemaName));
  const document = readJson(path.join(manifests, documentName));
  const validate = ajv.compile(schema);
  if (!validate(document)) {
    console.error(`${documentName} failed schema validation:`);
    console.error(ajv.errorsText(validate.errors, { separator: '\n' }));
    process.exitCode = 1;
  }
}

const suite = readJson(path.join(manifests, 'suite.json'));
const ids = new Set();
for (const component of suite.components) {
  if (ids.has(component.id)) {
    console.error(`Duplicate component id: ${component.id}`);
    process.exitCode = 1;
  }
  ids.add(component.id);

  for (const [index, url] of [component.source?.url, ...(component.source?.alternateUrls ?? [])].filter(Boolean).entries()) {
    if (new URL(url).protocol !== 'https:') {
      console.error(`${component.id}: source URL ${index + 1} must use HTTPS.`);
      process.exitCode = 1;
    }
  }

  let destination;
  try {
    if (component.destination) destination = safeRelative(component.destination, `${component.id} destination`);
    for (const expected of component.expectedRoots) {
      const normalizedExpected = safeRelative(expected, `${component.id} expected root`);
      if (component.distribution === 'bundled' && destination && normalizedExpected.toLowerCase() !== destination.toLowerCase()
          && !normalizedExpected.toLowerCase().startsWith(`${destination.toLowerCase()}/`)) {
        throw new Error(`${component.id} expected root is outside its component destination.`);
      }
    }
    if (component.source?.path) safeRelative(component.source.path, `${component.id} source path`);
    if (component.source?.asset) {
      if (component.source.asset.includes('/') || component.source.asset.includes('\\')
          || component.source.asset !== path.basename(component.source.asset)) {
        throw new Error(`${component.id} download asset must be a single filename.`);
      }
      safeRelative(component.source.asset, `${component.id} download asset`);
    }
    if (component.source?.archivePath) safeRelative(component.source.archivePath, `${component.id} archive member`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }

  if (component.distribution === 'bundled') {
    try {
      const sourcePath = resolveInsideRoot(component.source.path, `${component.id} bundled source`);
      if (!fs.existsSync(sourcePath)) {
        console.error(`Bundled component source is missing: ${component.source.path}`);
        process.exitCode = 1;
      }
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}

const hd = readJson(path.join(manifests, 'hd-patches.json'));
for (const patch of hd.patches) {
  for (const locale of hd.locales) {
    try {
      safeRelative(patch.pathTemplate.replaceAll('{locale}', locale), `${patch.id} HD path for ${locale}`);
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}

const provenance = readJson(path.join(manifests, 'media-provenance.json'));
for (const entry of provenance.allowedRoots) {
  let mediaRoot;
  let licensePath;
  try {
    mediaRoot = resolveInsideRoot(entry.path, `Media provenance root ${entry.path}`);
    licensePath = resolveInsideRoot(entry.licensePath, `Media license path ${entry.licensePath}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
    continue;
  }
  if (!fs.existsSync(mediaRoot)) {
    console.error(`Media provenance root is missing: ${entry.path}`);
    process.exitCode = 1;
  }
  if (!fs.existsSync(licensePath)) {
    console.error(`Media provenance license is missing: ${entry.licensePath}`);
    process.exitCode = 1;
  }
}

const waReview = readJson(path.join(manifests, 'wa-code-review.json'));
const reviewedPaths = new Set();
for (const entry of waReview.reviewedFiles) {
  try {
    const normalized = safeRelative(entry.path, `WeakAuras review path ${entry.path}`).toLowerCase();
    if (reviewedPaths.has(normalized)) throw new Error(`Duplicate WeakAuras review path: ${entry.path}`);
    reviewedPaths.add(normalized);
    const reviewedFile = resolveInsideRoot(entry.path, `WeakAuras review path ${entry.path}`);
    if (!fs.existsSync(reviewedFile)) throw new Error(`Reviewed WeakAuras file is missing: ${entry.path}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

if (!process.exitCode) {
  console.log(`Validated ${pairs.length} schemas, ${suite.components.length} components, and ${provenance.allowedRoots.length} media provenance roots.`);
}
