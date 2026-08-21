import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const suite = JSON.parse(fs.readFileSync(path.join(root, 'manifests', 'suite.json'), 'utf8'));
const errors = [];

function localPath(value) {
  return path.join(root, ...value.replaceAll('\\', '/').split('/'));
}

for (const component of suite.components) {
  const license = component.license;
  if (!license?.id || !license?.name || typeof license.redistributable !== 'boolean') {
    errors.push(`${component.id}: incomplete license record.`);
    continue;
  }

  if (component.distribution === 'bundled') {
    if (!license.redistributable) errors.push(`${component.id}: bundled component is not marked redistributable.`);
    if (!license.notice) {
      errors.push(`${component.id}: bundled component has no license notice.`);
    } else if (/^https?:\/\//i.test(license.notice)) {
      errors.push(`${component.id}: bundled license notice must be present in the repository.`);
    } else if (!fs.existsSync(localPath(license.notice))) {
      errors.push(`${component.id}: license notice is missing: ${license.notice}`);
    }
  }

  if (component.distribution === 'download') {
    for (const field of ['url', 'tag', 'asset', 'archivePath', 'sha256']) {
      if (!component.source?.[field]) errors.push(`${component.id}: download source is missing ${field}.`);
    }
    if (!/^[0-9a-f]{64}$/.test(component.source?.sha256 ?? '')) {
      errors.push(`${component.id}: download SHA-256 is not immutable lowercase hex.`);
    }
  }

  if (['link-only', 'detect-only'].includes(component.distribution) && component.availability !== 'gated' && license.redistributable) {
    errors.push(`${component.id}: external-only component should not claim bundled redistribution permission.`);
  }
}

const requiredNotices = [
  'LICENSE',
  'THIRD-PARTY-NOTICES.md',
  'licenses/OFL-PTSansNarrow.txt',
  'third_party/licenses/TidyPlates-MIT.txt',
  'third_party/licenses/ThreatPlates-GPL-3.0.txt',
];
for (const notice of requiredNotices) {
  if (!fs.existsSync(localPath(notice))) errors.push(`Required notice is missing: ${notice}`);
}

const thirdPartyPins = suite.components.filter((component) => ['tidyplates', 'threatplates'].includes(component.id));
for (const component of thirdPartyPins) {
  if (component.source.commit !== 'a668fc23d329356ad6e808fc084fd0f4094b43e3') {
    errors.push(`${component.id}: unexpected source commit.`);
  }
}

const fontRoot = localPath('packages/addons/WarmaneFontPack/fonts');
const fontLicenseRoot = localPath('packages/addons/WarmaneFontPack/licenses');
const fontNames = fs.readdirSync(fontRoot).filter((name) => name.toLowerCase().endsWith('.ttf')).map((name) => path.parse(name).name.toLowerCase()).sort();
const fontLicenseNames = fs.readdirSync(fontLicenseRoot).filter((name) => name.toLowerCase().endsWith('.txt')).map((name) => path.parse(name).name.toLowerCase()).sort();
for (const fontName of fontNames) {
  if (!fontLicenseNames.includes(fontName)) errors.push(`warmane-font-pack: font lacks a matching license record: ${fontName}.ttf`);
}
for (const licenseName of fontLicenseNames) {
  if (!fontNames.includes(licenseName)) errors.push(`warmane-font-pack: orphaned font license record: ${licenseName}.txt`);
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`License inventory passed for ${suite.components.length} components and ${requiredNotices.length} required notices.`);
}
