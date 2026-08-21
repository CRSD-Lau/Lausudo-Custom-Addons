import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument } from 'yaml';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const githubRoot = path.join(root, '.github');
const errors = [];
let count = 0;

function visit(value, file) {
  if (Array.isArray(value)) {
    for (const child of value) visit(child, file);
    return;
  }
  if (!value || typeof value !== 'object') return;
  if (typeof value.uses === 'string' && !value.uses.startsWith('./')) {
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.\/-]+)?@[0-9a-f]{40}$/.test(value.uses)) {
      errors.push(`${file}: action is not pinned to a full commit SHA: ${value.uses}`);
    }
  }
  for (const child of Object.values(value)) visit(child, file);
}

for (const relative of ['dependabot.yml', 'workflows/validate.yml', 'workflows/release.yml']) {
  const full = path.join(githubRoot, ...relative.split('/'));
  const document = parseDocument(fs.readFileSync(full, 'utf8'), { uniqueKeys: true, prettyErrors: true });
  count += 1;
  if (document.errors.length) {
    for (const error of document.errors) errors.push(`${relative}: ${error.message}`);
    continue;
  }
  const value = document.toJS();
  visit(value, relative);
  if (relative.startsWith('workflows/')) {
    if (!value.permissions || typeof value.permissions !== 'object') errors.push(`${relative}: explicit least-privilege permissions are required.`);
    if (value.on?.pull_request_target !== undefined) errors.push(`${relative}: pull_request_target is not permitted.`);
  }
  if (relative === 'workflows/release.yml' && Object.keys(value.on ?? {}).some((event) => event !== 'workflow_dispatch')) {
    errors.push(`${relative}: release mutation must remain manual workflow_dispatch only.`);
  }
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Parsed ${count} GitHub YAML files; all external actions use full commit pins.`);
}
