import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import luaparse from 'luaparse';

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`Missing required argument ${name}.`);
  return process.argv[index + 1];
}

const input = path.resolve(argument('--input'));
const output = path.resolve(argument('--output'));
const profileName = argument('--profile');
const repoRoot = path.resolve(argument('--repo-root'));
const privateStaging = path.join(repoRoot, '.private-staging');

function isWithin(parent, child) {
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function assertNoSymlinkInExistingPath(target) {
  const parsed = path.parse(target);
  let current = parsed.root;
  for (const segment of target.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    if (!fs.existsSync(current)) break;
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`Symlink or reparse-like output path is not allowed: ${current}`);
  }
}

if (isWithin(repoRoot, output) && !isWithin(privateStaging, output)) {
  throw new Error('Output inside the repository is allowed only under ignored .private-staging.');
}
if (input === output) throw new Error('Input and output paths must differ.');
if (fs.existsSync(output)) throw new Error('Output already exists.');
assertNoSymlinkInExistingPath(output);

function evaluate(node) {
  if (!node) return null;
  if (['StringLiteral', 'NumericLiteral', 'BooleanLiteral'].includes(node.type)) return node.value;
  if (node.type === 'NilLiteral') return null;
  if (node.type === 'UnaryExpression' && node.operator === '-' && node.argument.type === 'NumericLiteral') return -node.argument.value;
  if (node.type !== 'TableConstructorExpression') throw new Error(`Unsafe or unsupported Lua expression: ${node.type}`);

  const outputTable = Object.create(null);
  let arrayIndex = 1;
  for (const field of node.fields) {
    let key;
    if (field.type === 'TableKeyString') key = field.key.name;
    else if (field.type === 'TableKey') key = evaluate(field.key);
    else if (field.type === 'TableValue') key = arrayIndex++;
    else throw new Error(`Unsupported Lua table field: ${field.type}`);
    if (!['string', 'number'].includes(typeof key)) throw new Error('Lua table keys must be strings or numbers.');
    if (Object.prototype.hasOwnProperty.call(outputTable, key)) throw new Error(`Duplicate Lua table key: ${key}.`);
    outputTable[key] = evaluate(field.value);
  }
  return outputTable;
}

const inputStat = fs.statSync(input);
if (inputStat.size > 64 * 1024 * 1024) throw new Error('Explicit input exceeds the 64 MiB exporter safety limit.');
let luaSource = fs.readFileSync(input, 'utf8');
if (luaSource.charCodeAt(0) === 0xfeff) luaSource = luaSource.slice(1);
const ast = luaparse.parse(luaSource, {
  luaVersion: '5.1',
  encodingMode: 'pseudo-latin1',
});
let elvDbExpression;
for (const statement of ast.body) {
  if (statement.type !== 'AssignmentStatement') continue;
  for (let index = 0; index < statement.variables.length; index += 1) {
    const variable = statement.variables[index];
    if (variable.type === 'Identifier' && variable.name === 'ElvDB') elvDbExpression = statement.init[index];
  }
}
if (!elvDbExpression) throw new Error('ElvDB assignment was not found; no output was written.');

const database = evaluate(elvDbExpression);
const source = database?.profiles?.[profileName];
if (!source || typeof source !== 'object') throw new Error('The explicitly named profile was not found; no output was written.');

function valueAt(object, keys) {
  let value = object;
  for (const key of keys) {
    if (!value || typeof value !== 'object') return undefined;
    value = value[key];
  }
  return value;
}

const bannedKeys = new Set([
  'account', 'accounts', 'accountprofiles', 'character', 'characters', 'characterprofiles',
  'realm', 'realms', 'realmprofiles', 'profilekeys', 'history', 'chathistory',
  'combathistory', 'whisperhistory', 'channelhistory', 'bindings', 'keybindings',
  'macros', 'cache',
  '__proto__', 'constructor', 'prototype',
]);

function assertNoBannedKeys(value, trail = 'profile') {
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (bannedKeys.has(key.toLowerCase())) {
      throw new Error(`Banned identity, history, or gameplay key at ${trail}.${key}.`);
    }
    assertNoBannedKeys(child, `${trail}.${key}`);
  }
}

function sanitizeScalar(value) {
  if (typeof value === 'string') {
    if (/(?:gotham|melli|toxi)/i.test(value)) return 'PT Sans Narrow Bold';
    if (/(?:marty|reshade-shaders|WTF[\\/]|[A-Za-z]:[\\/]|\\\\[^\\]|https?:\/\/)/i.test(value)) {
      throw new Error('A selected visual field contains a banned path or external/private reference.');
    }
  }
  if (value === null || ['string', 'number', 'boolean'].includes(typeof value)) return value;
  throw new Error('A selected visual field contains an unsupported value type.');
}

function projectStrict(value, schema, trail) {
  if (schema === true) return sanitizeScalar(value);
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Expected a visual object at ${trail}.`);
  }
  for (const key of Object.keys(value)) {
    if (!(key in schema)) throw new Error(`Unknown visual key at ${trail}.${key}.`);
  }
  const outputValue = {};
  for (const [key, childSchema] of Object.entries(schema)) {
    if (value[key] !== undefined) outputValue[key] = projectStrict(value[key], childSchema, `${trail}.${key}`);
  }
  return outputValue;
}

function selectKnown(value, schema, trail) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const outputValue = {};
  for (const [key, childSchema] of Object.entries(schema)) {
    if (value[key] !== undefined) outputValue[key] = projectStrict(value[key], childSchema, `${trail}.${key}`);
  }
  return outputValue;
}

const color = { r: true, g: true, b: true, a: true };
const bar = {
  enabled: true, buttons: true, buttonsPerRow: true, buttonsize: true,
  buttonspacing: true, backdrop: true, showGrid: true,
};
const text = { text_format: true, position: true, xOffset: true, yOffset: true };
const power = { ...text, enable: true, height: true, width: true };
const portrait = { enable: true, width: true, overlay: true, fullOverlay: true, style: true };
const castbar = { enable: true, width: true, height: true, icon: true, iconSize: true };
const infoPanel = { enable: true, height: true };
const unit = {
  enable: true, width: true, height: true, orientation: true,
  disableMouseoverGlow: true, disableTargetGlow: true,
  health: text, power, name: text, portrait, castbar, infoPanel,
};
const powerColors = {
  MANA: color, RAGE: color, FOCUS: color, ENERGY: color, RUNIC_POWER: color,
  FUEL: color, HAPPINESS: color,
};

assertNoBannedKeys(source);

const visual = {};
visual.general = selectKnown(source.general, {
  font: true,
  fontSize: true,
  fontStyle: true,
  bordercolor: color,
  backdropcolor: color,
  backdropfadecolor: color,
  valuecolor: color,
  minimap: { size: true, locationText: true, locationFont: true, locationFontSize: true, locationFontOutline: true },
}, 'general');
visual.chat = selectKnown(source.chat, {
  font: true, fontSize: true, fontOutline: true, panelWidth: true, panelHeight: true,
  panelBackdrop: true, panelTabBackdrop: true, fade: true, fadeUndockedTabs: true,
}, 'chat');
visual.actionbar = selectKnown(source.actionbar, {
  font: true, fontSize: true, fontOutline: true, macrotext: true, hotkeytext: true,
  bar1: bar, bar2: bar, bar3: bar, bar4: bar, bar5: bar, bar6: bar,
  barPet: bar, stanceBar: bar, barTotem: bar,
}, 'actionbar');
visual.tooltip = selectKnown(source.tooltip, {
  font: true, fontSize: true, fontOutline: true,
  healthBar: { font: true, fontSize: true, fontOutline: true, height: true },
}, 'tooltip');

const unitframe = valueAt(source, ['unitframe']);
if (unitframe && typeof unitframe === 'object') {
  visual.unitframe = selectKnown(unitframe, {
    font: true,
    fontSize: true,
    fontOutline: true,
    statusbar: true,
    smoothbars: true,
    thinBorders: true,
    colors: {
      colorhealthbyvalue: true,
      healthclass: true,
      customhealthbackdrop: true,
      health: color,
      health_backdrop: color,
      power: powerColors,
    },
  }, 'unitframe');
  visual.unitframe.units = {};
  for (const unitName of ['player', 'target', 'targettarget', 'focus', 'pet', 'party', 'raid', 'raid40']) {
    const unitSource = unitframe.units?.[unitName];
    if (unitSource) visual.unitframe.units[unitName] = projectStrict(unitSource, unit, `unitframe.units.${unitName}`);
  }
}

const moverSource = valueAt(source, ['movers']);
if (moverSource && typeof moverSource === 'object') {
  visual.movers = {};
  for (const [key, value] of Object.entries(moverSource)) {
    if (!/^[A-Za-z0-9_]+Mover$|^ElvAB_[1-6]$|^ShiftAB$|^ElvBar_Totem$/.test(key)) continue;
    if (typeof value !== 'string' || !/^[A-Z]+,ElvUIParent,[A-Z]+,-?\d+,-?\d+$/.test(value)) {
      throw new Error('A selected mover contains an unsupported anchor value.');
    }
    visual.movers[key] = value;
  }
}

const result = {
  schemaVersion: 1,
  sourceType: 'sanitized-elvui-visual-profile',
  mediaSubstitution: 'restricted media replaced with PT Sans Narrow Bold',
  visual,
};

fs.mkdirSync(path.dirname(output), { recursive: true });
assertNoSymlinkInExistingPath(path.dirname(output));
assertNoSymlinkInExistingPath(output);
fs.writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
console.log('Sanitized visual profile written without account, character, realm, history, or source path metadata.');
