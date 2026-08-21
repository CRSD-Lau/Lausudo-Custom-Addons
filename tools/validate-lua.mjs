import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import luaparse from 'luaparse';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const scanRoots = ['packages', 'third_party/addons'];
const failures = [];
let count = 0;

function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.lua')) {
      count += 1;
      try {
        luaparse.parse(fs.readFileSync(full, 'utf8'), { luaVersion: '5.1' });
      } catch (error) {
        failures.push(`${path.relative(root, full)}: ${error.message}`);
      }
    }
  }
}

for (const relative of scanRoots) {
  const directory = path.join(root, ...relative.split('/'));
  if (fs.existsSync(directory)) walk(directory);
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Parsed ${count} Lua files as Lua 5.1.`);
}
