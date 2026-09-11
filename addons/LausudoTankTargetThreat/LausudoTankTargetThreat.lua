local targetThreat = CreateFrame("Frame")
local originalPostUpdate

local function UpdateTargetThreat(element, unit, status, ...)
	local frame = ElvUF_Target
	if unit ~= "target" or not frame or not frame.ThreatIndicator or not frame.db or frame.db.threatStyle ~= "GLOW"
		or not frame.ThreatIndicator.glow or not frame.ThreatIndicator.powerGlow then
		if originalPostUpdate then return originalPostUpdate(element, unit, status, ...) end
		return
	end

	local indicator = frame.ThreatIndicator
	if not UnitExists("target") or UnitIsDeadOrGhost("target") or not UnitCanAttack("player", "target") then
		indicator.glow:Hide()
		indicator.powerGlow:Hide()
		return
	end

	-- Requested tank rule: red while the target can/does have aggro; green only
	-- after you lose aggro but remain on the threat table (status 1).
	local r, g, b = 1, 0.12, 0.12
	if status == 1 then
		r, g, b = 0.15, 1, 0.30
	end

	indicator.glow:Show()
	indicator.glow:SetBackdropBorderColor(r, g, b)
	if frame.USE_POWERBAR_OFFSET then
		indicator.powerGlow:Show()
		indicator.powerGlow:SetBackdropBorderColor(r, g, b)
	else
		indicator.powerGlow:Hide()
	end
end

targetThreat:RegisterEvent("PLAYER_LOGIN")
targetThreat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if ElvUF_Target and ElvUF_Target.ThreatIndicator and ElvUF_Target.ThreatIndicator.ForceUpdate then
		originalPostUpdate = ElvUF_Target.ThreatIndicator.PostUpdate
		ElvUF_Target.ThreatIndicator.PostUpdate = UpdateTargetThreat
		ElvUF_Target.ThreatIndicator:ForceUpdate()
	end
end)
