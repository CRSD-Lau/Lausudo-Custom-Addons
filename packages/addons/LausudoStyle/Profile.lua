local addonName, ns = ...
local E = ns.E

local function buildProfile(font, scale)
	local profile = {
		general = {
			font = font,
			fontSize = 12,
			fontStyle = "OUTLINE",
			stickyFrames = true,
			minimap = {
				size = ns:ScaleOffset(200, scale),
				locationText = "SHOW",
				locationFont = font,
				locationFontSize = 12,
				locationFontOutline = "OUTLINE",
			},
			backdropcolor = { r = 0.035, g = 0.045, b = 0.055 },
			backdropfadecolor = { r = 0.035, g = 0.045, b = 0.055, a = 0.88 },
			bordercolor = { r = 0.12, g = 0.15, b = 0.18 },
			valuecolor = { r = 0.09, g = 0.52, b = 0.82 },
		},
		chat = {
			font = font,
			fontSize = 11,
			fontOutline = "OUTLINE",
			panelWidth = ns:ScaleOffset(410, scale),
			panelHeight = ns:ScaleOffset(180, scale),
			panelBackdrop = "SHOWBOTH",
			panelTabBackdrop = true,
			fade = true,
			fadeUndockedTabs = true,
		},
		actionbar = {
			font = font,
			fontSize = 11,
			fontOutline = "OUTLINE",
			macrotext = false,
			hotkeytext = true,
			bar1 = {
				enabled = true,
				buttons = 12,
				buttonsPerRow = 12,
				buttonsize = ns:ScaleOffset(34, scale),
				buttonspacing = 2,
				backdrop = false,
				showGrid = true,
			},
			bar2 = {
				enabled = true,
				buttons = 12,
				buttonsPerRow = 12,
				buttonsize = ns:ScaleOffset(30, scale),
				buttonspacing = 2,
				backdrop = false,
				showGrid = true,
			},
			bar3 = {
				enabled = true,
				buttons = 12,
				buttonsPerRow = 6,
				buttonsize = ns:ScaleOffset(30, scale),
				buttonspacing = 2,
				backdrop = false,
				showGrid = true,
			},
			bar4 = {
				enabled = true,
				buttons = 12,
				buttonsPerRow = 1,
				buttonsize = ns:ScaleOffset(30, scale),
				buttonspacing = 2,
				backdrop = true,
				showGrid = true,
			},
			bar5 = {
				enabled = true,
				buttons = 12,
				buttonsPerRow = 12,
				buttonsize = ns:ScaleOffset(28, scale),
				buttonspacing = 2,
				backdrop = false,
				showGrid = true,
			},
			barPet = {
				enabled = true,
				buttonsPerRow = 10,
				buttonsize = ns:ScaleOffset(28, scale),
				buttonspacing = 2,
			},
			stanceBar = {
				enabled = true,
				buttonsize = ns:ScaleOffset(28, scale),
				buttonspacing = 2,
			},
		},
		unitframe = {
			font = font,
			fontSize = 12,
			fontOutline = "OUTLINE",
			smoothbars = true,
			thinBorders = true,
			colors = {
				colorhealthbyvalue = false,
				healthclass = false,
				customhealthbackdrop = true,
				health = { r = 0.16, g = 0.19, b = 0.22 },
				health_backdrop = { r = 0.035, g = 0.045, b = 0.055 },
				power = { MANA = { r = 0.09, g = 0.40, b = 0.78 } },
			},
			units = {
				player = {
					enable = true,
					width = ns:ScaleOffset(250, scale),
					height = ns:ScaleOffset(58, scale),
					orientation = "RIGHT",
					disableMouseoverGlow = true,
					portrait = { enable = true, width = ns:ScaleOffset(55, scale), overlay = false, fullOverlay = false, style = "3D" },
					health = { text_format = "[healthcolor][health:current-percent]", position = "RIGHT", xOffset = -4, yOffset = 0 },
					power = { enable = true, height = ns:ScaleOffset(8, scale), text_format = "" },
					name = { text_format = "[namecolor][name]", position = "LEFT", xOffset = 4, yOffset = 0 },
					castbar = { enable = true, width = ns:ScaleOffset(250, scale), height = ns:ScaleOffset(22, scale), icon = true, iconSize = ns:ScaleOffset(22, scale) },
				},
				target = {
					enable = true,
					width = ns:ScaleOffset(250, scale),
					height = ns:ScaleOffset(58, scale),
					orientation = "LEFT",
					disableMouseoverGlow = true,
					portrait = { enable = true, width = ns:ScaleOffset(55, scale), overlay = false, fullOverlay = false, style = "3D" },
					health = { text_format = "[healthcolor][health:current-percent]", position = "LEFT", xOffset = 4, yOffset = 0 },
					power = { enable = true, height = ns:ScaleOffset(8, scale), text_format = "" },
					name = { text_format = "[namecolor][name:medium]", position = "RIGHT", xOffset = -4, yOffset = 0 },
					castbar = { enable = true, width = ns:ScaleOffset(250, scale), height = ns:ScaleOffset(22, scale), icon = true, iconSize = ns:ScaleOffset(22, scale) },
				},
				targettarget = {
					enable = true,
					width = ns:ScaleOffset(130, scale),
					height = ns:ScaleOffset(30, scale),
					portrait = { enable = false },
					health = { text_format = "[healthcolor][health:percent]", position = "RIGHT", xOffset = -3, yOffset = 0 },
					name = { text_format = "[namecolor][name:short]", position = "LEFT", xOffset = 3, yOffset = 0 },
					power = { enable = false },
				},
				focus = {
					enable = true,
					width = ns:ScaleOffset(180, scale),
					height = ns:ScaleOffset(36, scale),
					portrait = { enable = false },
					castbar = { enable = true, width = ns:ScaleOffset(180, scale), height = ns:ScaleOffset(18, scale), icon = true },
				},
				party = {
					enable = true,
					width = ns:ScaleOffset(180, scale),
					height = ns:ScaleOffset(42, scale),
					portrait = { enable = false },
				},
				raid = {
					enable = true,
					width = ns:ScaleOffset(82, scale),
					height = ns:ScaleOffset(34, scale),
				},
			},
		},
		tooltip = {
			font = font,
			fontSize = 11,
			fontOutline = "OUTLINE",
			healthBar = { font = font, fontSize = 11, fontOutline = "OUTLINE", height = 10 },
		},
	}

	local movers = {
		ElvUF_PlayerMover = ns:Mover("BOTTOM", "BOTTOM", -285, 205, scale),
		ElvUF_TargetMover = ns:Mover("BOTTOM", "BOTTOM", 285, 205, scale),
		ElvUF_TargetTargetMover = ns:Mover("BOTTOM", "BOTTOM", 345, 165, scale),
		ElvUF_FocusMover = ns:Mover("BOTTOM", "BOTTOM", 285, 285, scale),
		ElvUF_PlayerCastbarMover = ns:Mover("BOTTOM", "BOTTOM", -135, 145, scale),
		ElvUF_TargetCastbarMover = ns:Mover("BOTTOM", "BOTTOM", 135, 145, scale),
		ElvUF_PartyMover = ns:Mover("LEFT", "LEFT", 36, 50, scale),
		ElvUF_RaidMover = ns:Mover("BOTTOMLEFT", "BOTTOMLEFT", 36, 260, scale),
		ElvAB_1 = ns:Mover("BOTTOM", "BOTTOM", 0, 42, scale),
		ElvAB_2 = ns:Mover("BOTTOM", "BOTTOM", 0, 8, scale),
		ElvAB_3 = ns:Mover("BOTTOM", "BOTTOM", 0, 80, scale),
		ElvAB_4 = ns:Mover("RIGHT", "RIGHT", -8, 0, scale),
		ElvAB_5 = ns:Mover("BOTTOM", "BOTTOM", 0, 112, scale),
		MinimapMover = ns:Mover("TOPRIGHT", "TOPRIGHT", -18, -18, scale),
		LeftChatMover = ns:Mover("BOTTOMLEFT", "BOTTOMLEFT", 18, 18, scale),
		RightChatMover = ns:Mover("BOTTOMRIGHT", "BOTTOMRIGHT", -18, 18, scale),
	}
	profile.movers = movers
	return profile
end

function ns:ApplyElvUIProfile(mode, forceAspect)
	if not E or not E.data or not E.db then
		self:Print("ElvUI is not ready.")
		return false
	end

	local width, height, scale, supported = self:GetResolution()
	if not supported and not forceAspect then
		self:Print("refusing to apply at " .. width .. "x" .. height .. "; only 16:9 layouts are supported. Add 'force' to the slash command to override.")
		return false
	end

	local font, privateUsed = self:GetSelectedFont(mode)
	if mode == "private" and not privateUsed then
		self:Print("private font media was not detected; applying the safe font instead.")
		mode = "safe"
	end

	local current = E.data:GetCurrentProfile()
	local ownedName = self:GetOwnedProfileName(E.data, self.db.elvProfile, self.profileBaseName)
	if current ~= ownedName then self.db.previousElvProfile = current end
	self.db.elvProfile = ownedName
	self.db.mediaMode = mode

	E.data:SetProfile(ownedName)
	self:MarkCurrentProfileOwned(E.data)
	self:DeepMerge(E.db, buildProfile(font, scale))
	E:UpdateAll(true)
	self:CreateCursorHalo()
	self:Print("applied " .. ownedName .. " in " .. mode .. " media mode for " .. width .. "x" .. height .. ".")
	return true
end

function ns:RestoreElvUIProfile()
	if not E or not E.data then return false end
	local previous = self.db.previousElvProfile
	if not previous or not self:ProfileExists(E.data, previous) then
		self:Print("no previous ElvUI profile is available to restore.")
		return false
	end
	E.data:SetProfile(previous)
	E:UpdateAll(true)
	self:Print("restored the previous ElvUI profile.")
	return true
end
