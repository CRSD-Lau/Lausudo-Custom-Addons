local addonName, ns = ...
local E = unpack(ElvUI)

ns.addonName = addonName
ns.E = E
ns.profileBaseName = "Lausudo Style"
ns.schemaVersion = 1
ns.profileMarker = "LausudoStyle:1"

local floor = math.floor
local format = string.format
local pairs = pairs
local tonumber = tonumber
local type = type

local function round(value)
	if value >= 0 then return floor(value + 0.5) end
	return -floor(-value + 0.5)
end

function ns:Print(message)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1Lausudo Style:|r " .. tostring(message))
	end
end

function ns:DeepMerge(target, source)
	for key, value in pairs(source or {}) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then target[key] = {} end
			self:DeepMerge(target[key], value)
		else
			target[key] = value
		end
	end
	return target
end

function ns:ProfileExists(database, name)
	if not database or not database.GetProfiles then return false end
	local profiles = database:GetProfiles({})
	for index = 1, #profiles do
		if profiles[index] == name then return true end
	end
	return false
end

function ns:IsOwnedProfile(database, name)
	if not database or not name then return false end
	local profiles = database.profiles or (database.sv and database.sv.profiles)
	local profile = profiles and profiles[name]
	return profile and profile.lausudoStyleOwner == self.profileMarker
end

function ns:MarkCurrentProfileOwned(database)
	if database and database.profile then
		database.profile.lausudoStyleOwner = self.profileMarker
	end
end

function ns:GetOwnedProfileName(database, savedName, baseName)
	if savedName and self:IsOwnedProfile(database, savedName) then return savedName end
	local candidate = baseName
	local suffix = 2
	while self:ProfileExists(database, candidate) do
		if self:IsOwnedProfile(database, candidate) then return candidate end
		candidate = baseName .. " " .. suffix
		suffix = suffix + 1
	end
	return candidate
end

function ns:GetResolution()
	local width, height
	if GetScreenResolutions and GetCurrentResolution then
		local index = GetCurrentResolution()
		local resolutions = { GetScreenResolutions() }
		local current = resolutions[index or 0]
		if current then
			width, height = current:match("^(%d+)[xX](%d+)")
		end
	end

	width = tonumber(width) or (GetScreenWidth and GetScreenWidth()) or (UIParent and UIParent:GetWidth()) or 2560
	height = tonumber(height) or (GetScreenHeight and GetScreenHeight()) or (UIParent and UIParent:GetHeight()) or 1440
	local ratio = height > 0 and width / height or 0
	local supported = ratio > 1.76 and ratio < 1.79
	local scale = math.min(width / 2560, height / 1440)
	if scale < 0.75 then scale = 0.75 end
	if scale > 1 then scale = 1 end

	return round(width), round(height), scale, supported
end

function ns:ScaleOffset(value, scale)
	return round(value * (scale or 1))
end

function ns:Mover(point, relativePoint, x, y, scale)
	return format("%s,ElvUIParent,%s,%d,%d", point, relativePoint, self:ScaleOffset(x, scale), self:ScaleOffset(y, scale))
end

function ns:DetectPrivateMedia()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local detected = { available = false, font = nil, names = {} }
	if not LSM then return detected end

	local candidates = {
		"Gotham Narrow Ultra",
		"Gotham Narrow",
		"Melli",
	}
	for index = 1, #candidates do
		local name = candidates[index]
		local path = LSM:Fetch("font", name, true)
		if path then
			detected.names[#detected.names + 1] = name
			if not detected.font then detected.font = name end
		end
	end

	detected.available = detected.font ~= nil
	return detected
end

function ns:GetSafeFont()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM:Fetch("font", "PT Sans Narrow Bold", true) then return "PT Sans Narrow Bold" end
	if LSM and LSM:Fetch("font", "PT Sans Narrow", true) then return "PT Sans Narrow" end
	return "Arial Narrow"
end

function ns:GetSelectedFont(mode)
	if mode == "private" then
		local detected = self:DetectPrivateMedia()
		if detected.available then return detected.font, true end
	end
	return self:GetSafeFont(), false
end

function ns:EnsureDatabase()
	LausudoStyleDB = LausudoStyleDB or {}
	local defaults = {
		schemaVersion = self.schemaVersion,
		cursorEnabled = true,
		mediaMode = "safe",
		elvProfile = nil,
		previousElvProfile = nil,
		threatProfile = nil,
		previousThreatProfile = nil,
	}
	for key, value in pairs(defaults) do
		if LausudoStyleDB[key] == nil then LausudoStyleDB[key] = value end
	end
	LausudoStyleDB.schemaVersion = self.schemaVersion
	self.db = LausudoStyleDB
end

function ns:CreateCursorHalo()
	if self.cursorFrame then return end
	local frame = CreateFrame("Frame", "LausudoStyleCursorHalo", UIParent)
	frame:SetWidth(42)
	frame:SetHeight(42)
	frame:SetFrameStrata("TOOLTIP")
	frame:EnableMouse(false)
	local texture = frame:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints(frame)
	texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	texture:SetBlendMode("ADD")
	texture:SetVertexColor(0.09, 0.52, 0.82, 0.55)
	frame.texture = texture
	frame:SetScript("OnUpdate", function(cursor)
		if not ns.db or not ns.db.cursorEnabled then
			cursor:Hide()
			return
		end
		local x, y = GetCursorPosition()
		local effectiveScale = UIParent:GetEffectiveScale()
		cursor:ClearAllPoints()
		cursor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / effectiveScale, y / effectiveScale)
	end)
	self.cursorFrame = frame
	if self.db.cursorEnabled then frame:Show() else frame:Hide() end
end

function ns:SetCursorEnabled(enabled)
	self.db.cursorEnabled = enabled and true or false
	if self.cursorFrame then
		if self.db.cursorEnabled then self.cursorFrame:Show() else self.cursorFrame:Hide() end
	end
	self:Print("cursor halo " .. (self.db.cursorEnabled and "enabled" or "disabled") .. ".")
end

function ns:GetStatusText()
	local width, height, _, supported = self:GetResolution()
	local media = self:DetectPrivateMedia()
	local profile = self.db and self.db.elvProfile or "not installed"
	return format(
		"profile: %s; resolution: %dx%d (%s); private media: %s; cursor: %s",
		profile,
		width,
		height,
		supported and "supported 16:9" or "unsupported aspect ratio",
		media.available and "detected" or "not detected",
		self.db and self.db.cursorEnabled and "on" or "off"
	)
end
