"""Public package and Lua 5.1 regression checks. Author: Neil Mitchell."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('suite', ROOT / 'tools/suite.py')
suite = importlib.util.module_from_spec(spec)
spec.loader.exec_module(suite)


class Packages(unittest.TestCase):
    def test_public_tree(self):
        self.assertGreater(suite.validate(), 500)

    def test_dependencies(self):
        _, modules = suite.catalog()
        self.assertEqual(suite.resolve(modules, ['combat-text']), ['nameplates', 'combat-text'])
        self.assertEqual(suite.resolve(modules, ['group-bubbles']), ['fonts', 'group-bubbles'])
        with self.assertRaises(ValueError): suite.resolve(modules, ['unknown'])
        with self.assertRaises(ValueError): suite.resolve({'a': {'requires': ['b']}, 'b': {'requires': ['a']}}, ['a'])

    def test_private_and_unsafe_names(self):
        for name in ['WTF/Account/user.lua', 'x/LOGINui-old.lua', 'LoginUI.lua.zip', '../escape',
                     '/absolute', 'a//b', 'a\\b', 'C:/file', 'a/CON.txt', 'a/trailing.', 'a/space ', 'SavedVariables/a.lua']:
            with self.subTest(name=name), self.assertRaises(ValueError): suite.safe_name(name)

    def test_windows_toc_case_rules(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'commands.lua').write_text('-- fixture')
            self.assertTrue(suite.windows_file(root, 'Commands.lua'))
            self.assertFalse(suite.windows_file(root, 'Missing.lua'))

    def test_credential_content_is_redacted(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'file.lua'
            secret = 'gh' + 'p_' + 'a' * 36
            path.write_text(secret)
            with self.assertRaises(ValueError) as error: suite.read_public(path)
            self.assertNotIn(secret, str(error.exception))

    def test_addon_source_scope(self):
        _, modules = suite.catalog()
        files = suite.source_files(ROOT, modules, ['combat-text'])
        self.assertTrue(any('/TidyPlates/' in f for f in files))
        self.assertTrue(any('/CrispFCT/' in f for f in files))
        self.assertFalse(any('/LausudoSuite/' in f for f in files))
        self.assertIn('licenses/OFL-PTSansNarrow.txt', files)

    def test_build_determinism_and_metadata(self):
        first = suite.build(selected=['core'])
        initial = first.read_bytes()
        suite.build(selected=['core'])
        self.assertEqual(initial, first.read_bytes())
        with zipfile.ZipFile(first) as archive:
            manifest = json.loads(archive.read('package-manifest.json'))
            self.assertEqual(manifest['author'], 'Neil Mitchell')
            self.assertEqual(manifest['lastModifiedBy'], 'Neil Mitchell')
            self.assertIn(b'Neil Mitchell', archive.comment)
        self.assertFalse((ROOT / 'dist/verification').exists())

    def test_tampering_and_unexpected_members(self):
        with tempfile.TemporaryDirectory() as folder:
            archive_path = Path(folder) / 'bad.zip'
            raw = b'original'
            manifest = {'files': {'readme.txt': {'size': len(raw), 'sha256': suite.digest(raw)}}}
            for extra, content in [(None, b'modified'), ('LoginUI.lua', raw), ('extra.txt', raw), ('README.TXT', raw)]:
                with zipfile.ZipFile(archive_path, 'w') as archive:
                    archive.writestr('package-manifest.json', json.dumps(manifest))
                    archive.writestr('readme.txt', content)
                    if extra: archive.writestr(extra, 'unwanted')
                with self.subTest(extra=extra), self.assertRaises(ValueError): suite.verify(archive_path)

    def test_subset_cannot_overwrite_all(self):
        path = suite.build(selected=['core', 'fonts'])
        self.assertIn('-core+fonts.zip', path.name)
        with zipfile.ZipFile(path) as archive:
            self.assertEqual(set(json.loads(archive.read('package-manifest.json'))['modules']), {'core', 'fonts'})

    def test_all_lua_parses_as_51(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        parse = lua.eval('function(s) local f,e = loadstring(s); return f ~= nil,e end')
        for folder in ['addons', 'third_party/addons']:
            for path in (ROOT / folder).rglob('*.lua'):
                ok, error = parse(path.read_text(encoding='utf-8-sig'))
                self.assertTrue(ok, str(path.relative_to(ROOT)) + ': ' + str(error))


MOCK = '''
suite = {db = {}}
messages = {}
function suite:Print(s) table.insert(messages, s) end
player, realm, combat = "Tester", "TestRealm", false
function UnitName() return player end
function GetRealmName() return realm end
function InCombatLockdown() return combat end
function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k,v in pairs(value) do result[k] = copy(v) end; return result
end
db = {profiles = {Original = {custom = 42, general = {font = "Mine"}}}, current = "Original"}
db.profile = db.profiles.Original
function db:GetProfiles() local list = {}; for k in pairs(self.profiles) do table.insert(list,k) end; return list end
function db:GetCurrentProfile() return self.current end
function db:SetProfile(name)
    self.profiles[name] = self.profiles[name] or {}
    self.current, self.profile = name, self.profiles[name]
end
function db:CopyProfile(name) for k,v in pairs(copy(self.profiles[name])) do self.profile[k] = v end end
function db:DeleteProfile(name) if name ~= self.current then self.profiles[name] = nil end end
E = {data = db, UpdateAll = function() if fail then error("fixture refresh failure") end end}
ElvUI = {E}
TidyPlatesThreat = {db = db, ConfigRefresh = function() end}
'''


class Profiles(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute((ROOT / 'addons/LausudoSuite/Profiles.lua').read_text(), 'LausudoSuite', self.lua.globals().suite)

    def test_apply_restore_preserves_existing(self):
        self.lua.execute('''
assert(suite:Profile("elvui", false))
assert(db.current ~= "Original" and db.profile.custom == 42)
assert(db.profiles.Original.general.font == "Mine")
assert(suite:Profile("elvui", true))
assert(db.current == "Original")
''')

    def test_repeat_keeps_customizations(self):
        self.lua.execute('''
suite:Profile("elvui", false)
local owned = db.current
db.profile.general.font = "Customized"
suite:Profile("elvui", false)
assert(db.current == owned and db.profile.general.font == "Customized")
assert(suite.db.elvui.previous == "Original")
suite:Profile("elvui", true)
suite:Profile("elvui", false)
assert(db.current == owned and db.profile.general.font == "Customized")
''')

    def test_collision_and_character_isolation(self):
        self.lua.execute('''
db.profiles["Lausudo Suite - Tester - TestRealm"] = {untouched = true}
suite:Profile("elvui", false)
local first = db.current
assert(first == "Lausudo Suite - Tester - TestRealm 2")
assert(db.profiles["Lausudo Suite - Tester - TestRealm"].untouched)
suite.db = {}; player = "Second"
db:SetProfile("Original")
suite:Profile("elvui", false)
assert(db.current ~= first)
''')

    def test_combat_missing_api_and_missing_restore(self):
        self.lua.execute('''
combat = true; assert(not suite:Profile("elvui", false)); assert(db.current == "Original")
combat = false; assert(not suite:Profile("elvui", true))
db.CopyProfile = nil; assert(not suite:Profile("elvui", false))
assert(db.current == "Original")
''')

    def test_failure_rolls_back(self):
        self.lua.execute('''
fail = true; assert(not suite:Profile("elvui", false))
assert(db.current == "Original")
assert(#db:GetProfiles() == 1 and suite.db.elvui == nil)
''')

    def test_nameplate_profile(self):
        self.lua.execute('''
assert(suite:Profile("nameplates", false))
assert(db.profile.settings.healthbar.width == 130)
assert(suite:Profile("nameplates", true))
assert(db.current == "Original")
''')

    def test_real_bundled_acedb(self):
        self.lua.execute('''
function CreateFrame() return {RegisterEvent = function() end, SetScript = function() end} end
function UnitClass() return "Paladin", "PALADIN" end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function GetLocale() return "enUS" end
function GetCVar() return "enUS" end
function geterrorhandler() return error end
strmatch = string.match
''')
        for name in ['addons/WarmaneFontPack/Libs/LibStub/LibStub.lua',
                     'addons/WarmaneFontPack/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua',
                     'third_party/addons/TidyPlates_ThreatPlates/Libs/AceDB-3.0/AceDB-3.0.lua']:
            self.lua.execute((ROOT / name).read_text(encoding='utf-8-sig'))
        self.lua.execute('''
db = LibStub("AceDB-3.0"):New({}, {profile = {general = {font = "OriginalFont"}}}, "Original")
E.data = db
db.profile.custom = 42
assert(suite:Profile("elvui", false))
assert(db:GetCurrentProfile() ~= "Original" and db.profile.custom == 42)
assert(suite:Profile("elvui", true))
assert(db:GetCurrentProfile() == "Original" and db.profile.general.font == "OriginalFont")
''')


class OptionalModules(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
SlashCmdList = {}; DEFAULT_CHAT_FRAME = {AddMessage = function() end}
function CreateFrame()
    local frame = {RegisterEvent = function() end, UnregisterEvent = function() end}
    function frame:SetScript(_, fn) self.callback = fn end
    lastFrame = frame; return frame
end
''')

    def load(self, relative, namespace=None):
        self.lua.execute((ROOT / 'addons' / relative).read_text(encoding='utf-8-sig'), 'TestAddon', namespace)

    def test_unsupported_modules_are_inert(self):
        namespace = self.lua.table()
        self.load('LausudoGroupBubbles/ElvUIStyle.lua', namespace)
        self.load('LausudoGroupBubbles/LausudoGroupBubbles.lua', namespace)
        self.load('LausudoHoPRange/LausudoHoPRange.lua')
        self.assertIsNone(self.lua.globals().lastFrame)

    def test_paladin_range_has_no_character_lock(self):
        self.lua.execute('''
UF = {UpdateRange = function() fallback = true end}
ElvUI = {{GetModule = function() return UF end, Libs = {SpellRange = {IsSpellInRange = function() return range end}}}}
class, range, connected = "PALADIN", 1, true
function UnitClass() return "Any name", class end
function UnitIsUnit() return false end
function UnitIsConnected() return connected end
function UnitIsDeadOrGhost() return false end
function UnitCanAssist() return true end
raid = {unit = "raid1", Fader = {MaxAlpha = 1, MinAlpha = 0.2}}
''')
        self.load('LausudoHoPRange/LausudoHoPRange.lua')
        self.lua.execute('''
UF.UpdateRange(raid); assert(raid.Fader.RangeAlpha == 1)
connected = false; UF.UpdateRange(raid); assert(raid.Fader.RangeAlpha == 0.2)
class = "MAGE"; UF.UpdateRange(raid); assert(fallback)
''')

    def test_tank_threat_colors_and_fallback(self):
        self.lua.execute('''
function glow() return {Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end,
    SetBackdropBorderColor = function(self, r,g,b) self.r,self.g,self.b = r,g,b end} end
indicator = {glow = glow(), powerGlow = glow(), ForceUpdate = function() end,
    PostUpdate = function() fallback = true end}
ElvUF_Target = {ThreatIndicator = indicator, db = {threatStyle = "GLOW"}}
function UnitExists() return true end
function UnitIsDeadOrGhost() return false end
function UnitCanAttack() return true end
''')
        self.load('LausudoTankTargetThreat/LausudoTankTargetThreat.lua')
        self.lua.execute('''
lastFrame.callback(lastFrame)
indicator.PostUpdate(indicator, "target", 0); assert(indicator.glow.r == 1)
indicator.PostUpdate(indicator, "target", 1); assert(indicator.glow.g == 1)
ElvUF_Target.db.threatStyle = "NONE"
indicator.PostUpdate(indicator, "target", 1); assert(fallback)
''')

    def test_group_style_preserves_recipient_font(self):
        self.lua.execute('''
M = {SkinBubble = function() end, UpdateBubbleBorder = function() end, AddChatBubbleName = function() end}
style = {GetName = function() return "style" end}
E = {private = {general = {chatBubbleFont = "MyFont", chatBubbles = "backdrop"}},
    GetModule = function() return M end, NewModule = function() return style end,
    RegisterModule = function() style:Initialize() end}
ElvUI = {E}
''')
        self.load('LausudoGroupBubbles/ElvUIStyle.lua', self.lua.table())
        self.lua.execute('assert(E.private.general.chatBubbleFont == "MyFont" and style.ready)')


if __name__ == '__main__': unittest.main()
