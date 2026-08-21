local addonName, ns = ...

local function applyThreatSettings(profile, font)
	profile.verbose = false
	profile.friendlyNameOnly = false
	profile.healthColorChange = false
	profile.customColor = false
	profile.nameplate = profile.nameplate or {}
	profile.nameplate.scale = profile.nameplate.scale or {}
	profile.nameplate.scale.Target = 1.18
	profile.nameplate.scale.Boss = 1.12
	profile.nameplate.scale.Elite = 1.06
	profile.nameplate.scale.Normal = 1
	profile.nameplate.scale.Neutral = 0.92

	profile.settings = profile.settings or {}
	local settings = profile.settings
	settings.healthbar = settings.healthbar or {}
	settings.healthbar.texture = "ThreatPlatesBar"
	settings.healthbar.width = 130
	settings.healthbar.height = 10
	settings.healthborder = settings.healthborder or {}
	settings.healthborder.texture = "TP_HealthBarOverlayThin"
	settings.healthborder.show = true
	settings.elitehealthborder = settings.elitehealthborder or {}
	settings.elitehealthborder.texture = "TP_HealthBarEliteOverlayThin"
	settings.elitehealthborder.show = true
	settings.castbar = settings.castbar or {}
	settings.castbar.texture = "ThreatPlatesBar"
	settings.castbar.x = 0
	settings.castbar.y = -20
	settings.castbar.show = true
	settings.castborder = settings.castborder or {}
	settings.castborder.x = 0
	settings.castborder.y = -20
	settings.castborder.show = true

	local fontKeys = { "name", "level", "customtext", "spelltext" }
	for index = 1, #fontKeys do
		local key = fontKeys[index]
		settings[key] = settings[key] or {}
		settings[key].typeface = font
		settings[key].flags = "OUTLINE"
		settings[key].shadow = true
	end
	settings.name.size = 15
	settings.name.y = 14
	settings.level.size = 12
	settings.customtext.size = 12
	settings.spelltext.size = 12
end

function ns:ApplyThreatPlatesProfile(mode)
	local threat = _G.TidyPlatesThreat
	if not threat or not threat.db then
		self:Print("Threat Plates is not loaded; its profile was not changed.")
		return false
	end

	local font, privateUsed = self:GetSelectedFont(mode)
	if mode == "private" and not privateUsed then font = self:GetSafeFont() end
	local database = threat.db
	local current = database:GetCurrentProfile()
	local owned = self:GetOwnedProfileName(database, self.db.threatProfile, self.profileBaseName)
	if current ~= owned then self.db.previousThreatProfile = current end
	self.db.threatProfile = owned
	database:SetProfile(owned)
	self:MarkCurrentProfileOwned(database)
	applyThreatSettings(database.profile, font)
	if threat.ConfigRefresh then threat:ConfigRefresh() end
	self:Print("applied the " .. owned .. " Threat Plates profile.")
	return true
end

function ns:RestoreThreatPlatesProfile()
	local threat = _G.TidyPlatesThreat
	if not threat or not threat.db then return false end
	local previous = self.db.previousThreatProfile
	if not previous or not self:ProfileExists(threat.db, previous) then
		self:Print("no previous Threat Plates profile is available to restore.")
		return false
	end
	threat.db:SetProfile(previous)
	if threat.ConfigRefresh then threat:ConfigRefresh() end
	self:Print("restored the previous Threat Plates profile.")
	return true
end
