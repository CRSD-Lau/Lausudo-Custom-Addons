local addonName, VisualCore = ...

VisualCore = VisualCore or {}
_G.LausudoVisualCore = VisualCore

local AURA_BASE_ID = "Lausudo Combat Focus Ring"
local PACK_VERSION = 1

local function printMessage(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1Lausudo Visual Core:|r " .. message)
end

local function findAvailableId()
	if LausudoVisualCoreDB.auraId and LausudoVisualCoreDB.auraUid then
		local saved = WeakAuras.GetData(LausudoVisualCoreDB.auraId)
		if saved and saved.uid == LausudoVisualCoreDB.auraUid then
			return LausudoVisualCoreDB.auraId
		end
	end
	if not WeakAuras.GetData(AURA_BASE_ID) then return AURA_BASE_ID end
	local suffix = 2
	while WeakAuras.GetData(AURA_BASE_ID .. " " .. suffix) do suffix = suffix + 1 end
	return AURA_BASE_ID .. " " .. suffix
end

local function buildAura(id)
	local data = { id = id, regionType = "texture", uid = LausudoVisualCoreDB.auraUid }
	WeakAuras.DeepMixin(data, WeakAuras.data_stub)
	data.internalVersion = WeakAuras.InternalVersion()
	WeakAuras.validate(data, WeakAuras.regionTypes.texture.default)
	data.texture = "Interface\\Buttons\\UI-ActionButton-Border"
	data.width = 54
	data.height = 54
	data.color = { 0.09, 0.52, 0.82, 0.45 }
	data.blendMode = "ADD"
	data.selfPoint = "CENTER"
	data.anchorPoint = "CENTER"
	data.anchorFrameType = "SCREEN"
	data.xOffset = 0
	data.yOffset = -36
	data.frameStrata = 1
	data.triggers = {
		{
			trigger = {
				type = "custom",
				custom_type = "status",
				check = "event",
				events = "PLAYER_ENTERING_WORLD PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED",
				custom = "function() return UnitAffectingCombat('player') and true or false end",
				custom_hide = "custom",
			},
			untrigger = {
				custom = "function() return not UnitAffectingCombat('player') end",
			},
		},
		activeTriggerMode = 1,
		disjunctive = "all",
	}
	data.information = {
		description = "Original visual-only combat focus ring authored for the Lausudo Warmane UI Suite.",
	}
	return data
end

function VisualCore:Install()
	if not WeakAuras or not WeakAuras.Add or not WeakAuras.GetData then
		printMessage("WeakAuras is not ready.")
		return false
	end
	LausudoVisualCoreDB = LausudoVisualCoreDB or {}
	local id = findAvailableId()
	local existing = WeakAuras.GetData(id)
	local owned = existing and LausudoVisualCoreDB.auraId == id and LausudoVisualCoreDB.auraUid and existing.uid == LausudoVisualCoreDB.auraUid
	if existing and not owned then
		printMessage("an unrelated aura uses the planned name; no data was overwritten.")
		return false
	end

	local data = buildAura(id)
	WeakAuras.Add(data, existing and true or false)
	local installed = WeakAuras.GetData(id)
	if not installed then
		printMessage("WeakAuras did not confirm installation.")
		return false
	end
	if not installed.uid then
		printMessage("this WeakAuras version did not provide a durable aura UID; future updates will not overwrite this display.")
	end
	LausudoVisualCoreDB.auraId = id
	LausudoVisualCoreDB.auraUid = installed.uid
	LausudoVisualCoreDB.packVersion = PACK_VERSION
	printMessage("installed " .. id .. ".")
	return true
end

SLASH_LAUSUDOVISUALCORE1 = "/lausudowa"
SlashCmdList.LAUSUDOVISUALCORE = function(message)
	local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
	if command == "install" then
		VisualCore:Install()
	else
		printMessage("nothing changes automatically. Use /lausudowa install to add or update the reviewed visual aura.")
	end
end
