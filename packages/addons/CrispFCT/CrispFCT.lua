-- Crisp outgoing and selectively filtered incoming combat text for 3.3.5.
--
-- Wrath's native world text only exposes DAMAGE_TEXT_FONT; its low-resolution
-- outline and animation are compiled into the client.  This renderer uses a
-- pre-rendered PT Sans Narrow texture atlas so legacy FontString size caps cannot make
-- every hit tier identical.  It attaches hits only when TidyPlates can identify a
-- mob safely.  When several visible mobs share a name, hits float around that
-- pack's centre rather than being assigned to a random plate.

local FCT = CreateFrame("Frame")

local GLYPH_ATLAS = "Interface\\AddOns\\CrispFCT\\media\\CrispFCTGlyphs"
local THREAT_FONT = "Interface\\AddOns\\CrispFCT\\fonts\\PTSansNarrow-Bold.ttf"
local ATLAS_WIDTH = 1024
local ATLAS_HEIGHT = 128
local CELL_WIDTH = 64
local SOURCE_GLYPH_HEIGHT = 58
local GLYPHS = {
	["0"] = { 0, 0, 64 }, ["1"] = { 1, 0, 64 },
	["2"] = { 2, 0, 64 }, ["3"] = { 3, 0, 64 },
	["4"] = { 4, 0, 64 }, ["5"] = { 5, 0, 64 },
	["6"] = { 6, 0, 64 }, ["7"] = { 7, 0, 64 },
	["8"] = { 8, 0, 64 }, ["9"] = { 9, 0, 64 },
	["."] = { 10, 0, 64 }, ["K"] = { 11, 0, 64 },
	["M"] = { 12, 0, 64 }, ["B"] = { 13, 0, 64 },
	["!"] = { 14, 0, 64 }, ["-"] = { 15, 0, 64 },
}

local OUTGOING_COLOR = { 1, 1, 1, 1 }
local INCOMING_DAMAGE_COLOR = { 1, 0.30, 0.22, 1 }
local INCOMING_HEAL_COLOR = { 0.28, 1, 0.24, 1 }

-- These ICC families should remain visible even if mitigation pushes the final
-- hit below the generic large-damage threshold.  IDs come from the installed
-- DBM Icecrown modules for all 10/25 normal/heroic variants.
local PRIORITY_INCOMING_SPELLS = {
	[69409] = true, [73797] = true, [73798] = true, [73799] = true, -- Soul Reaper
	[69649] = true, [71056] = true, [71057] = true, [71058] = true, -- Frost Breath P1
	[73061] = true, [73062] = true, [73063] = true, [73064] = true, -- Frost Breath P2
}
local PRIORITY_INCOMING_NAMES = {
	["Frost Breath"] = true,
	["Soul Reaper"] = true,
}

local DEFAULTS = {
	enabled = true,
	version = 16,
	fontSize = 12,
	bigHitThreshold = 1000,
	bigHitMultiplier = 4 / 3,
	critMultiplier = 5 / 3,
	renderMode = "atlas",
	outline = "OUTLINE",
	duration = 1.4,
	hold = 0.58,
	rise = 54,
	offsetY = 30,
	spread = 42,
	incomingDamageMin = 6000,
	incomingDamageHealthPct = 0.15,
	incomingSwingMin = 12000,
	incomingSwingHealthPct = 0.25,
	incomingHealMin = 5000,
	incomingHealHealthPct = 0.10,
	incomingAnchorY = 0.42,
	incomingRise = 58,
	enteringCombat = true,
	threatMessagesEnabled = true,
	threatAttackingYou = true,
	threatLosingThreat = true,
	threatChangedTarget = true,
	threatMessageSize = 21,
	threatMessageDuration = 1.4,
	threatMessageRise = 46,
	threatMessageAnchorY = 0.46,
	maxTexts = 20,
}

local DB
local clusterPool = {}
local incomingPool = {}
local threatPool = {}
local plateHosts = setmetatable({}, { __mode = "k" })
local fountainDirection = -1
local lastThreatTargetGUID, lastThreatVictimGUID, lastThreatStatus
local floor = math.floor
local max = math.max
local random = math.random
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type

local function round(value)
	return floor((value or 0) + 0.5)
end

local function isCritical(value)
	return value == true or value == 1
end

local function hasCombatLogFlag(flags, mask)
	if not bit or not mask or flags == nil then return false end
	return bit.band(flags, mask) ~= 0
end

local function isHostileReaction(flags)
	if not bit or not COMBATLOG_OBJECT_REACTION_HOSTILE or flags == nil then return true end
	return hasCombatLogFlag(flags, COMBATLOG_OBJECT_REACTION_HOSTILE)
end

local function isNpcSource(flags)
	if not bit or flags == nil then return true end
	return hasCombatLogFlag(flags, COMBATLOG_OBJECT_TYPE_NPC or 0x00000800)
end

local function playerScaledThreshold(minimum, healthPct)
	local maximumHealth = tonumber(UnitHealthMax("player")) or 0
	return max(tonumber(minimum) or 0, round(maximumHealth * (tonumber(healthPct) or 0)))
end

local function setCVar(name, value)
	pcall(SetCVar, name, value)
end

local function copyDefaults(target)
	for key, value in pairs(DEFAULTS) do
		if target[key] == nil then target[key] = value end
	end
end

local function getFontSize(amount, critical)
	local multiplier = 1
	local tier = "normal"
	if critical then
		multiplier = DB.critMultiplier
		tier = "critical"
	elseif amount >= DB.bigHitThreshold then
		multiplier = DB.bigHitMultiplier
		tier = "big"
	end
	return round(DB.fontSize * multiplier), tier, multiplier
end

local function shortAmount(amount)
	amount = tonumber(amount) or 0
	if amount >= 1000000000 then return string.format("%.1fB", amount / 1000000000) end
	if amount >= 1000000 then return string.format("%.1fM", amount / 1000000) end
	if amount >= 1000 then return string.format("%.1fK", amount / 1000) end
	return tostring(amount)
end

local function acquireGlyph(object, index)
	local texture = object.glyphs[index]
	if texture then return texture end
	texture = object.glyphFrame:CreateTexture(nil, "OVERLAY")
	texture:SetTexture(GLYPH_ATLAS)
	texture:SetBlendMode("BLEND")
	object.glyphs[index] = texture
	return texture
end

local function renderGlyphText(object, message, size, color)
	color = color or OUTGOING_COLOR
	local textureHeight = round(size * ATLAS_HEIGHT / SOURCE_GLYPH_HEIGHT)
	local gap = max(1, round(size * 0.06))
	local rendered = {}
	local totalWidth = 0

	for index = 1, string.len(message) do
		local character = string.sub(message, index, index)
		local metric = GLYPHS[character]
		if metric then
			local cell, left, right = metric[1], metric[2], metric[3]
			local width = max(1, round((right - left) * textureHeight / ATLAS_HEIGHT))
			rendered[#rendered + 1] = { cell, left, right, width }
			totalWidth = totalWidth + width
		end
	end
	if #rendered > 1 then totalWidth = totalWidth + gap * (#rendered - 1) end

	object.glyphFrame:SetWidth(max(1, totalWidth))
	object.glyphFrame:SetHeight(textureHeight)
	local offset = 0
	for index = 1, #rendered do
		local data = rendered[index]
		local texture = acquireGlyph(object, index)
		local cellStart = data[1] * CELL_WIDTH
		local u0 = (cellStart + data[2] + 0.5) / ATLAS_WIDTH
		local u1 = (cellStart + data[3] - 0.5) / ATLAS_WIDTH
		texture:ClearAllPoints()
		texture:SetPoint("LEFT", object.glyphFrame, "LEFT", offset, 0)
		texture:SetWidth(data[4])
		texture:SetHeight(textureHeight)
		texture:SetTexCoord(u0, u1, 0, 1)
		texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		texture:Show()
		offset = offset + data[4] + gap
	end
	for index = #rendered + 1, #object.glyphs do
		object.glyphs[index]:Hide()
	end

	object.renderedHeight = textureHeight
	object.renderedWidth = totalWidth
end

local function createTextObject(parent)
	local object = CreateFrame("Frame", nil, parent)
	object:SetWidth(260)
	object:SetHeight(54)
	object:SetFrameStrata("TOOLTIP")

	local glyphFrame = CreateFrame("Frame", nil, object)
	glyphFrame:SetWidth(1)
	glyphFrame:SetHeight(1)
	glyphFrame:SetPoint("CENTER", object, "CENTER")
	object.glyphFrame = glyphFrame
	object.glyphs = {}
	object:Hide()

	object:SetScript("OnUpdate", function(frame, elapsed)
		if frame.host then
			local plate = frame.host.plate
			local visible = _G.TidyPlates and _G.TidyPlates.NameplatesByVisible
			local unit = plate and plate.extended and plate.extended.unit
			if not plate or not visible or not visible[plate] or not plate:IsShown() or not unit
				or (frame.destGUID and unit.guid and unit.guid ~= frame.destGUID)
				or (frame.destName and unit.name and unit.name ~= frame.destName) then
				frame:Hide()
				return
			end
		end

		frame.elapsed = frame.elapsed + elapsed
		local progress = frame.elapsed / frame.duration
		if progress >= 1 then
			frame:Hide()
			return
		end

		local travel = progress
		if frame.motion == "fountain" then
			-- Ease outward from the centre so regular hits fan up like a fountain
			-- instead of merely spawning at unrelated horizontal offsets.
			travel = 1 - (1 - progress) * (1 - progress)
		end
		local x = frame.startX + (frame.driftX or 0) * travel
		local y = frame.startY + frame.rise * travel
		frame:ClearAllPoints()
		if frame.host then
			frame:SetPoint("CENTER", frame.host, "CENTER", round(x), round(y))
		else
			frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", round(frame.screenX + x), round(frame.screenY + y))
		end

		if progress <= frame.hold then
			frame:SetAlpha(1)
		else
			frame:SetAlpha((1 - progress) / (1 - frame.hold))
		end
	end)

	return object
end

-- The damage renderer is an intentionally numbers-only texture atlas. Threat
-- notices use the same Crisp FCT animation lane with the bundled OFL font
-- font so the three readable state messages are not limited to numeric glyphs.
local function createThreatMessageObject()
	local object = CreateFrame("Frame", nil, UIParent)
	object:SetWidth(420)
	object:SetHeight(42)
	object:SetFrameStrata("TOOLTIP")
	object.text = object:CreateFontString(nil, "OVERLAY")
	object.text:SetPoint("CENTER")
	object.text:SetJustifyH("CENTER")
	object.text:SetShadowColor(0, 0, 0, 1)
	object.text:SetShadowOffset(1, -1)
	object:Hide()

	object:SetScript("OnUpdate", function(frame, elapsed)
		frame.elapsed = frame.elapsed + elapsed
		local progress = frame.elapsed / frame.duration
		if progress >= 1 then
			frame:Hide()
			return
		end

		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", frame.screenX, round(frame.screenY + frame.rise * progress))
		if progress <= frame.hold then
			frame:SetAlpha(1)
		else
			frame:SetAlpha((1 - progress) / (1 - frame.hold))
		end
	end)

	return object
end

local function acquireObject(pool, parent)
	for index = 1, #pool do
		if not pool[index]:IsShown() then return pool[index] end
	end

	if #pool < DB.maxTexts then
		local object = createTextObject(parent)
		pool[#pool + 1] = object
		return object
	end

	local oldest = pool[1]
	for index = 2, #pool do
		if pool[index].elapsed > oldest.elapsed then oldest = pool[index] end
	end
	return oldest
end

local function acquireThreatMessage()
	for index = 1, #threatPool do
		if not threatPool[index]:IsShown() then return threatPool[index] end
	end

	if #threatPool < 3 then
		local object = createThreatMessageObject()
		threatPool[#threatPool + 1] = object
		return object
	end

	return threatPool[1]
end

local function getPlateHost(plate)
	local host = plateHosts[plate]
	if host then
		host.plate = plate
		return host
	end

	local parent = plate.extended or plate
	host = CreateFrame("Frame", nil, parent)
	host:SetAllPoints(parent)
	host:SetFrameStrata("TOOLTIP")
	host.plate = plate
	host.pool = {}
	plateHosts[plate] = host
	return host
end

local function startText(object, host, screenX, screenY, amount, critical, destGUID, destName, options)
	options = options or {}
	object.host = host
	object.destGUID = destGUID
	object.destName = destName
	object.screenX = screenX or 0
	object.screenY = screenY or 0
	object.duration = options.duration or DB.duration
	object.hold = options.hold or DB.hold
	object.rise = options.rise or DB.rise
	object.elapsed = 0
	object.motion = options.motion or (critical and "vertical" or "fountain")
	if options.startY ~= nil then
		object.startY = options.startY
	else
		object.startY = DB.offsetY + random(-4, 4)
	end

	if options.startX ~= nil then
		object.startX = options.startX
	elseif object.motion == "fountain" then
		object.startX = random(-5, 5)
	else
		-- Crits get a narrow lane but never drift horizontally while moving.
		object.startX = random(-3, 3)
	end

	if options.driftX ~= nil then
		object.driftX = options.driftX
	elseif object.motion == "fountain" then
		local maximumDrift = max(12, round(DB.spread))
		local minimumDrift = max(10, round(maximumDrift * 0.65))
		fountainDirection = -fountainDirection
		object.driftX = fountainDirection * random(minimumDrift, maximumDrift)
	else
		object.driftX = 0
	end

	local size = options.size or getFontSize(amount, critical)
	-- Reset these dimensions on every reuse so a prior critical hit cannot
	-- leave a normal hit with an oversized animation frame.
	local message = options.message or shortAmount(amount)
	if critical and options.appendCritical ~= false then message = message .. "!" end
	renderGlyphText(object, message, size, options.color or OUTGOING_COLOR)
	object:SetWidth(max(260, object.renderedWidth + 20))
	object:SetHeight(max(54, object.renderedHeight + 10))
	object:SetAlpha(1)
	object:Show()
end

local function isVisiblePlate(plate)
	local visible = _G.TidyPlates and _G.TidyPlates.NameplatesByVisible
	return plate and visible and visible[plate] and plate:IsShown() and plate.extended and plate.extended.unit
end

local function getCandidates(name)
	local result = {}
	local visible = _G.TidyPlates and _G.TidyPlates.NameplatesByVisible
	if not visible or not name then return result end

	for plate in pairs(visible) do
		local unit = plate.extended and plate.extended.unit
		if plate:IsShown() and unit and unit.name == name then
			result[#result + 1] = plate
		end
	end
	return result
end

local function resolvePlate(guid, name)
	local tidy = _G.TidyPlates
	local verified = tidy and tidy.NameplatesByGUID and tidy.NameplatesByGUID[guid]
	if isVisiblePlate(verified) and verified.extended.unit.guid == guid then
		return verified
	end

	local candidates = getCandidates(name)
	for index = 1, #candidates do
		if candidates[index].extended.unit.guid == guid then
			return candidates[index]
		end
	end

	if UnitGUID("target") == guid then
		for index = 1, #candidates do
			if candidates[index].extended.unit.isTarget then
				return candidates[index]
			end
		end
	end

	if UnitGUID("mouseover") == guid then
		for index = 1, #candidates do
			if candidates[index].extended.unit.isMouseover then
				return candidates[index]
			end
		end
	end

	return nil, candidates
end

local function getPackCenter(candidates)
	local totalX, totalY, count = 0, 0, 0
	local uiScale = UIParent:GetEffectiveScale() or 1
	for index = 1, #candidates do
		local anchor = candidates[index].extended or candidates[index]
		local x, y = anchor:GetCenter()
		if x and y then
			local scale = anchor:GetEffectiveScale() or uiScale
			totalX = totalX + x * scale / uiScale
			totalY = totalY + y * scale / uiScale
			count = count + 1
		end
	end
	if count == 0 then return end
	return totalX / count, totalY / count
end

function FCT:DisplayDamage(guid, name, amount, critical)
	if not DB or not DB.enabled or type(amount) ~= "number" or amount <= 0 then return end

	local plate, candidates = resolvePlate(guid, name)
	if plate then
		local host = getPlateHost(plate)
		local object = acquireObject(host.pool, host)
		startText(object, host, nil, nil, amount, critical, guid, name)
		return "plate", object
	end

	-- Name-only candidates cannot be attached safely in 3.3.5 because TidyPlates
	-- recycles its frames.  Render at the current screen-space centre instead;
	-- this preserves AoE text without letting a recycled plate carry old damage.
	if candidates and #candidates > 0 then
		local x, y = getPackCenter(candidates)
		if x and y then
			local object = acquireObject(clusterPool, UIParent)
			startText(object, nil, x, y, amount, critical, guid, name)
			return "cluster", object
		end
	end
end

function FCT:DisplayIncoming(amount, kind, critical, prominent)
	if not DB or not DB.enabled or type(amount) ~= "number" or amount <= 0 then return end
	local object = acquireObject(incomingPool, UIParent)
	local width = UIParent:GetWidth() or 0
	local height = UIParent:GetHeight() or 0
	local isHeal = kind == "heal"
	local lane = isHeal and -52 or 52
	local color = isHeal and INCOMING_HEAL_COLOR or INCOMING_DAMAGE_COLOR
	local message = (isHeal and "" or "-") .. shortAmount(amount)
	local size = getFontSize(amount, prominent or critical)

	startText(object, nil, width / 2, height * DB.incomingAnchorY, amount, critical, nil, nil, {
		motion = "vertical",
		startX = lane + random(-4, 4),
		startY = 0,
		driftX = 0,
		rise = DB.incomingRise,
		size = size,
		message = message,
		color = color,
	})
	return object
end

local THREAT_MESSAGES = {
	enteringCombat = { text = "ENTERING COMBAT", color = { 1, 0.82, 0.18, 1 } },
	attackingYou = { text = "ATTACKING YOU", color = { 0.30, 1, 0.35, 1 } },
	losingThreat = { text = "LOSING THREAT", color = { 1, 0.32, 0.18, 1 } },
	changedTarget = { text = "CHANGED TARGET", color = { 1, 0.82, 0.18, 1 } },
}

local function grouped()
	return (GetNumRaidMembers and GetNumRaidMembers() > 0) or (GetNumPartyMembers and GetNumPartyMembers() > 0)
end

local pendingLossGUID
local lossConfirmation = CreateFrame("Frame")
lossConfirmation:Hide()
lossConfirmation:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 0.18 then return end
	self:Hide()
	local targetGUID = pendingLossGUID
	pendingLossGUID = nil

	-- The client can report a threat transition immediately before UNIT_DIED.
	-- Confirm it one short frame later: a living mob with a living non-player
	-- victim is a real aggro swap; anything else is just a death cleanup.
	if not targetGUID or not FCT.inCombat or UnitGUID("target") ~= targetGUID then return end
	if not UnitExists("target") or UnitIsDeadOrGhost("target") or (UnitHealth("target") or 0) <= 0 then return end
	local victimGUID = UnitGUID("targettarget")
	if not victimGUID or victimGUID == UnitGUID("player") then return end
	if UnitIsDeadOrGhost("targettarget") or (UnitHealth("targettarget") or 0) <= 0 then return end
	FCT:DisplayThreatMessage("losingThreat")
end)

function FCT:DisplayThreatMessage(kind)
	if not DB or not DB.enabled then return end
	if kind == "enteringCombat" then
		if not DB.enteringCombat then return end
	elseif not DB.threatMessagesEnabled then
		return
	end
	if kind == "attackingYou" and not DB.threatAttackingYou then return end
	if kind == "losingThreat" and not DB.threatLosingThreat then return end
	if kind == "changedTarget" and not DB.threatChangedTarget then return end
	-- Threat loss is only meaningful to the raid/party UI.  Solo creatures can
	-- clear threat one frame before their death event, which is noisy and useless.
	if kind == "losingThreat" and not grouped() then return end

	local message = THREAT_MESSAGES[kind]
	if not message then return end
	local object = acquireThreatMessage()
	object.text:SetFont(THREAT_FONT, DB.threatMessageSize, "OUTLINE")
	object.text:SetTextColor(message.color[1], message.color[2], message.color[3], message.color[4])
	object.text:SetText(message.text)
	object.elapsed = 0
	object.duration = DB.threatMessageDuration
	object.hold = DB.hold
	object.rise = DB.threatMessageRise
	object.screenX = round((UIParent:GetWidth() or 0) / 2)
	object.screenY = round((UIParent:GetHeight() or 0) * DB.threatMessageAnchorY)
	object:SetAlpha(1)
	object:Show()
	return object
end

function FCT:QueueLosingThreat()
	if not grouped() or not UnitExists("target") then return end
	pendingLossGUID = UnitGUID("target")
	lossConfirmation.elapsed = 0
	lossConfirmation:Show()
end

function FCT:RefreshThreatState()
	if not DB or not DB.enabled or not DB.threatMessagesEnabled then return end
	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		lastThreatTargetGUID, lastThreatVictimGUID, lastThreatStatus = nil, nil, nil
		return
	end

	local targetGUID = UnitGUID("target")
	local victimGUID = UnitGUID("targettarget")
	local playerGUID = UnitGUID("player")
	local status = UnitThreatSituation and UnitThreatSituation("player", "target") or 0
	status = status or 0
	local victimIsAlive = victimGUID and UnitExists("targettarget") and not UnitIsDeadOrGhost("targettarget") and (UnitHealth("targettarget") or 0) > 0
	-- A dying target often clears targettarget and its threat state in the same
	-- frame.  That is a death transition, not a meaningful loss of threat.
	if UnitIsDeadOrGhost("target") or (UnitHealth("target") or 0) <= 0 then
		lastThreatTargetGUID, lastThreatVictimGUID, lastThreatStatus = targetGUID, victimGUID, status
		return
	end
	if targetGUID ~= lastThreatTargetGUID then
		lastThreatTargetGUID, lastThreatVictimGUID, lastThreatStatus = targetGUID, victimGUID, status
		return
	end

	local announced = false
	if self.inCombat and victimGUID ~= lastThreatVictimGUID then
		if lastThreatVictimGUID then
			-- When the change is specifically to or from the tank, the direct
			-- aggro callout is more useful than stacking two alerts in one lane.
			if victimGUID == playerGUID and lastThreatVictimGUID ~= playerGUID then
				self:DisplayThreatMessage("attackingYou")
			elseif lastThreatVictimGUID == playerGUID and victimGUID ~= playerGUID then
				if victimIsAlive then self:QueueLosingThreat() end
			else
				self:DisplayThreatMessage("changedTarget")
			end
			announced = true
		end
	end

	if self.inCombat and status ~= lastThreatStatus and not announced then
		if status == 3 and lastThreatStatus < 3 then
			self:DisplayThreatMessage("attackingYou")
		elseif status < 3 and lastThreatStatus == 3 and victimIsAlive then
			self:QueueLosingThreat()
		end
	end
	lastThreatVictimGUID, lastThreatStatus = victimGUID, status
end

local DAMAGE_EVENTS = {
	SWING_DAMAGE = true,
	RANGE_DAMAGE = true,
	SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true,
	SPELL_BUILDING_DAMAGE = true,
	DAMAGE_SHIELD = true,
	DAMAGE_SPLIT = true,
}

local HEAL_EVENTS = {
	SPELL_HEAL = true,
	SPELL_PERIODIC_HEAL = true,
	SPELL_BUILDING_HEAL = true,
}

local function getDamagePayload(subEvent, ...)
	if not DAMAGE_EVENTS[subEvent] then return end
	local amount, critical, spellId, spellName
	local swing = subEvent == "SWING_DAMAGE"
	if swing then
		amount, _, _, _, _, _, critical = select(9, ...)
	else
		spellId, spellName = select(9, ...)
		amount, _, _, _, _, _, critical = select(12, ...)
	end
	return tonumber(amount), isCritical(critical), tonumber(spellId), spellName, swing
end

local function getHealPayload(subEvent, ...)
	if not HEAL_EVENTS[subEvent] then return end
	local spellId, spellName = select(9, ...)
	local amount, overhealing, _, critical = select(12, ...)
	amount = tonumber(amount)
	if not amount then return end
	local effective = max(0, amount - (tonumber(overhealing) or 0))
	return effective, isCritical(critical), tonumber(spellId), spellName
end

function FCT:CombatLogEvent(...)
	if not self.inCombat and not UnitAffectingCombat("player") and not UnitAffectingCombat("pet") then return end
	local _, subEvent, sourceGUID, _, sourceFlags, destGUID, destName, destFlags = ...
	local playerGUID = UnitGUID("player")
	local petGUID = UnitGUID("pet")

	-- Incoming is intentionally sparse: effective critical heals only, and
	-- hostile damage large enough to matter to a tank.  Native incoming FCT
	-- remains disabled, so these cannot double with Blizzard numbers.
	if destGUID == playerGUID then
		local healAmount, healCritical = getHealPayload(subEvent, ...)
		if healAmount then
			local threshold = playerScaledThreshold(DB.incomingHealMin, DB.incomingHealHealthPct)
			if healCritical and healAmount >= threshold then
				self:DisplayIncoming(healAmount, "heal", true, true)
			end
			return
		end

		local incomingAmount, incomingCritical, spellId, spellName, swing = getDamagePayload(subEvent, ...)
		if incomingAmount then
			local priority = PRIORITY_INCOMING_SPELLS[spellId] or PRIORITY_INCOMING_NAMES[spellName]
			if priority or (isHostileReaction(sourceFlags) and isNpcSource(sourceFlags)) then
				local threshold
				if swing then
					threshold = playerScaledThreshold(DB.incomingSwingMin, DB.incomingSwingHealthPct)
				else
					threshold = playerScaledThreshold(DB.incomingDamageMin, DB.incomingDamageHealthPct)
				end
				if priority or incomingAmount >= threshold then
					self:DisplayIncoming(incomingAmount, "damage", incomingCritical, priority)
				end
			end
			return
		end
	end

	if sourceGUID ~= playerGUID and sourceGUID ~= petGUID then return end
	if not isHostileReaction(destFlags) then return end
	local amount, critical = getDamagePayload(subEvent, ...)
	if not amount or amount <= 0 then return end
	self:DisplayDamage(destGUID, destName, amount, critical)
end

local function hidePool(pool)
	for index = 1, #(pool or {}) do
		local object = pool[index]
		object:Hide()
		object.host = nil
		object.destGUID = nil
		object.destName = nil
	end
end

function FCT:ClearActiveTexts()
	hidePool(clusterPool)
	hidePool(incomingPool)
	hidePool(threatPool)
	for _, host in pairs(plateHosts) do
		hidePool(host.pool)
	end
end

local CONTROLLED_CVARS = {
	"enableCombatText",
	"CombatHealing",
	"CombatDamage",
	"CombatLogPeriodicSpells",
	"PetMeleeDamage",
	"PetSpellDamage",
	"fctCombatState",
}

local function captureNativeWorldDamage()
	DB.nativeCvars = {}
	for index = 1, #CONTROLLED_CVARS do
		local name = CONTROLLED_CVARS[index]
		DB.nativeCvars[name] = GetCVar(name)
	end
	DB.nativeCombatStateGlobalWasNil = COMBAT_TEXT_SHOW_COMBAT_STATE == nil
	DB.nativeCombatStateGlobal = COMBAT_TEXT_SHOW_COMBAT_STATE
end

local function useCustomWorldDamage()
	-- With the custom renderer active, suppress Blizzard's overlapping streams.
	setCVar("enableCombatText", 0)
	setCVar("CombatHealing", 0)
	setCVar("CombatDamage", 0)
	setCVar("CombatLogPeriodicSpells", 0)
	setCVar("PetMeleeDamage", 0)
	setCVar("PetSpellDamage", 0)
	setCVar("fctCombatState", 0)
	COMBAT_TEXT_SHOW_COMBAT_STATE = "0"
end

local function restoreNativeWorldDamage()
	if not DB or not DB.nativeCvars then return end
	for index = 1, #CONTROLLED_CVARS do
		local name = CONTROLLED_CVARS[index]
		local value = DB.nativeCvars[name]
		if value ~= nil then setCVar(name, value) end
	end
	if DB.nativeCombatStateGlobalWasNil then
		COMBAT_TEXT_SHOW_COMBAT_STATE = nil
	elseif DB.nativeCombatStateGlobal ~= nil then
		COMBAT_TEXT_SHOW_COMBAT_STATE = DB.nativeCombatStateGlobal
	end
end

function FCT:Activate()
	if not _G.TidyPlates or not _G.TidyPlates.NameplatesByVisible then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff3333Crisp FCT:|r TidyPlates is unavailable; native combat-text settings were left unchanged.")
		return false
	end

	if not self.active then
		captureNativeWorldDamage()
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		self:RegisterEvent("PLAYER_LOGOUT")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
		self:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
		self:RegisterEvent("UNIT_TARGET")
		self.active = true
	end
	self.inCombat = UnitAffectingCombat("player") and true or false
	_G.CrispFCTActive = true
	useCustomWorldDamage()
	return true
end

function FCT:Deactivate()
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:UnregisterEvent("PLAYER_LOGOUT")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	self:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	self:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
	self:UnregisterEvent("UNIT_TARGET")
	self:ClearActiveTexts()
	self.inCombat = false
	self.active = false
	_G.CrispFCTActive = nil
	restoreNativeWorldDamage()
end

function FCT:PlayerLogin()
	self:UnregisterEvent("PLAYER_LOGIN")
	CrispFCTDB = CrispFCTDB or {}
	CrispFCTDB.worldCombatText = CrispFCTDB.worldCombatText or {}
	DB = CrispFCTDB.worldCombatText
	local previousVersion = tonumber(DB.version) or 0
	copyDefaults(DB)
	if previousVersion < 12 then
		DB.fontSize = DEFAULTS.fontSize
		DB.bigHitMultiplier = DEFAULTS.bigHitMultiplier
		DB.critMultiplier = DEFAULTS.critMultiplier
	end
	if previousVersion < 13 then
		DB.duration = DEFAULTS.duration
		DB.rise = DEFAULTS.rise
		DB.spread = DEFAULTS.spread
		DB.incomingDamageMin = DEFAULTS.incomingDamageMin
		DB.incomingDamageHealthPct = DEFAULTS.incomingDamageHealthPct
		DB.incomingSwingMin = DEFAULTS.incomingSwingMin
		DB.incomingSwingHealthPct = DEFAULTS.incomingSwingHealthPct
		DB.incomingHealMin = DEFAULTS.incomingHealMin
		DB.incomingHealHealthPct = DEFAULTS.incomingHealHealthPct
		DB.incomingAnchorY = DEFAULTS.incomingAnchorY
		DB.incomingRise = DEFAULTS.incomingRise
	end
	if previousVersion < 14 then
		DB.threatMessagesEnabled = DEFAULTS.threatMessagesEnabled
		DB.threatAttackingYou = DEFAULTS.threatAttackingYou
		DB.threatLosingThreat = DEFAULTS.threatLosingThreat
		DB.threatChangedTarget = DEFAULTS.threatChangedTarget
		DB.threatMessageSize = DEFAULTS.threatMessageSize
		DB.threatMessageDuration = DEFAULTS.threatMessageDuration
		DB.threatMessageRise = DEFAULTS.threatMessageRise
		DB.threatMessageAnchorY = DEFAULTS.threatMessageAnchorY
	end
	if previousVersion < 15 then
		DB.enteringCombat = DEFAULTS.enteringCombat
	end
	if previousVersion < 16 then
		DB.nativeCvars = nil
		DB.nativeCombatStateGlobal = nil
		DB.nativeCombatStateGlobalWasNil = nil
	end
	DB.critFontSize = nil
	DB.version = DEFAULTS.version
	DB.renderMode = DEFAULTS.renderMode

	if DB.enabled and self:Activate() then
		DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1Crisp FCT:|r enabled; 1.4s fountain normals, vertical crits, and filtered major incoming events.")
	end
end

FCT:RegisterEvent("PLAYER_LOGIN")
FCT:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		self:PlayerLogin()
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		self:CombatLogEvent(...)
	elseif event == "PLAYER_REGEN_DISABLED" then
		self.inCombat = true
		self:DisplayThreatMessage("enteringCombat")
	elseif event == "PLAYER_REGEN_ENABLED" then
		self.inCombat = false
		self:ClearActiveTexts()
		lastThreatTargetGUID, lastThreatVictimGUID, lastThreatStatus = nil, nil, nil
	elseif event == "PLAYER_LOGOUT" then
		restoreNativeWorldDamage()
	elseif event == "PLAYER_TARGET_CHANGED" then
		self:RefreshThreatState()
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_TARGET" then
		if ... == "target" or ... == "player" then self:RefreshThreatState() end
	end
end)

function FCT:GetSettings()
	return DB
end

function FCT:SetEnabled(enabled)
	if not DB then return end
	DB.enabled = enabled and true or false
	if DB.enabled then self:Activate() else self:Deactivate() end
end

function FCT:PreviewThreatMessage()
	self.previewThreatIndex = (self.previewThreatIndex or 0) + 1
	local sequence = { "attackingYou", "losingThreat", "changedTarget" }
	return self:DisplayThreatMessage(sequence[((self.previewThreatIndex - 1) % #sequence) + 1])
end

_G.CrispFCT = FCT

SLASH_CRISPFCT1 = "/crispfct"
SlashCmdList.CRISPFCT = function(message)
	if not DB then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Crisp FCT:|r available after login.")
		return
	end

	local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
	if command == "on" then
		DB.enabled = true
		if FCT:Activate() then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Crisp FCT:|r enabled.") end
	elseif command == "off" then
		DB.enabled = false
		FCT:Deactivate()
		DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Crisp FCT:|r disabled; native world damage restored.")
	elseif command == "test" then
		local guid, name = UnitGUID("target"), UnitName("target")
		if not guid then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Crisp FCT:|r select a target first.")
		else
			local route, normalObject = FCT:DisplayDamage(guid, name, 650, false)
			local _, bigObject = FCT:DisplayDamage(guid, name, 2400, false)
			local _, critObject = FCT:DisplayDamage(guid, name, 12345, true)
			if normalObject then normalObject.startX = -80 end
			if bigObject then bigObject.startX = 0 end
			if critObject then critObject.startX = 90 end
			if route then
				local normalSize = getFontSize(650, false)
				local bigSize = getFontSize(2400, false)
				local critSize = getFontSize(12345, true)
				local normalHeight = normalObject and normalObject.renderedHeight or 0
				local bigHeight = bigObject and bigObject.renderedHeight or 0
				local critHeight = critObject and critObject.renderedHeight or 0
				DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Crisp FCT:|r atlas targets " .. normalSize .. "px / " .. bigSize .. "px / " .. critSize .. "px; texture heights " .. normalHeight .. " / " .. bigHeight .. " / " .. critHeight .. "; fountain normals and vertical crits run for " .. DB.duration .. "s by the " .. route .. " route.")
			else
				DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Crisp FCT:|r no visible TidyPlates match for the selected target.")
			end
		end
	elseif command == "testin" then
		local damageThreshold = playerScaledThreshold(DB.incomingDamageMin, DB.incomingDamageHealthPct)
		local healThreshold = playerScaledThreshold(DB.incomingHealMin, DB.incomingHealHealthPct)
		FCT:DisplayIncoming(max(damageThreshold, 6000), "damage", false, false)
		FCT:DisplayIncoming(max(healThreshold, 5000), "heal", true, true)
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Crisp FCT:|r incoming test; red major damage threshold " .. shortAmount(damageThreshold) .. ", green effective critical-heal threshold " .. shortAmount(healThreshold) .. ".")
	elseif command == "threat" then
		FCT:PreviewThreatMessage()
	else
		local state = DB.enabled and "enabled" or "disabled"
		DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1Crisp FCT:|r " .. state .. ". Commands: /crispfct on, off, test, testin, threat")
	end
end
