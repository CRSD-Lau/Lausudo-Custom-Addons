local ADDON_NAME = ...

local E = ElvUI and ElvUI[1]
local UF = E and E.GetModule and E:GetModule("UnitFrames", true)
local SpellRange = E and E.Libs and E.Libs.SpellRange
if not UF or type(UF.UpdateRange) ~= "function" or not SpellRange or type(SpellRange.IsSpellInRange) ~= "function" then
	DEFAULT_CHAT_FRAME:AddMessage("Lausudo HoP Range: unsupported ElvUI range API; module inactive.")
	return
end

local HOP_SPELL_ID = 1022 -- Base ID; LibSpellRange resolves the learned rank.
local originalUpdateRange = UF.UpdateRange

local UnitCanAssist = UnitCanAssist
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit

local function IsEnabledForThisCharacter()
	local _, class = UnitClass("player")
	return class == "PALADIN"
end

local function IsRaidUnit(unit)
	return type(unit) == "string" and string.match(unit, "^raid%d+$") ~= nil
end

function UF:UpdateRange(unit)
	unit = unit or self.unit

	if not IsEnabledForThisCharacter() or not IsRaidUnit(unit) then
		return originalUpdateRange(self, unit)
	end

	if not self.Fader then
		return
	end

	local inRange = false
	if UnitIsUnit(unit, "player") then
		inRange = true
	elseif UnitIsConnected(unit)
		and not UnitIsDeadOrGhost(unit)
		and UnitCanAssist("player", unit)
		and SpellRange.IsSpellInRange(HOP_SPELL_ID, unit) == 1 then
		inRange = true
	end

	self.Fader.RangeAlpha = inRange and self.Fader.MaxAlpha or self.Fader.MinAlpha
end

SLASH_LAUSUDOHOPRANGE1 = "/hoprange"
SlashCmdList.LAUSUDOHOPRANGE = function()
	local active = IsEnabledForThisCharacter()
	local raid = E.db and E.db.unitframe and E.db.unitframe.units and E.db.unitframe.units.raid
	local fader = raid and raid.fader
	E:Print(("%s: %s. Raid fader: %s; range: %s; alpha: %.2f to %.2f."):format(
		ADDON_NAME,
		active and "active for Hand of Protection" or "inactive on this character",
		fader and fader.enable and "enabled" or "disabled",
		fader and fader.range and "enabled" or "disabled",
		fader and fader.minAlpha or 0,
		fader and fader.maxAlpha or 1
	))
end
