local addonName, ns = ...
local E = ns.E

local function setPageText(title, first, second, third)
	PluginInstallFrame.SubTitle:SetText(title or "")
	PluginInstallFrame.Desc1:SetText(first or "")
	PluginInstallFrame.Desc2:SetText(second or "")
	PluginInstallFrame.Desc3:SetText(third or "")
end

local function welcomePage()
	local width, height, _, supported = ns:GetResolution()
	setPageText(
		"Privacy-safe visual setup",
		"This installer creates new addon profiles through supported in-game APIs. It does not import account mappings, chat, keybinds, macros, history, or SavedVariables files.",
		"Detected resolution: " .. width .. "x" .. height .. ". " .. (supported and "The 16:9 layout is supported." or "This aspect ratio is not supported and apply will be blocked by default."),
		"Nothing is applied automatically. Continue to choose a media mode."
	)
end

local function stylePage()
	local media = ns:DetectPrivateMedia()
	setPageText(
		"Choose visual media",
		"Safe mode uses redistribution-safe PT Sans Narrow media and is the recommended public setup.",
		media.available and "Private font media was detected in your existing addon registrations. Exact mode may reference it in place, but never copies it." or "No supported private font media is currently registered.",
		"Applying creates a new profile and records the previously selected profile for restoration."
	)
	PluginInstallFrame.Option1:Show()
	PluginInstallFrame.Option1:SetText("Apply safe style")
	PluginInstallFrame.Option1:SetScript("OnClick", function() ns:ApplyElvUIProfile("safe", false) end)
	if media.available then
		PluginInstallFrame.Option2:Show()
		PluginInstallFrame.Option2:SetText("Use detected media")
		PluginInstallFrame.Option2:SetScript("OnClick", function() ns:ApplyElvUIProfile("private", false) end)
	end
end

local function integrationsPage()
	setPageText(
		"Optional integrations",
		"Threat Plates can receive its own new visual profile through AceDB. Existing profiles are not overwritten.",
		"The separately packaged Lausudo Visual Core can install one original, reviewed WeakAura on explicit request.",
		"Private fonts, HD patches, ReShade shaders, LUTs, and third-party WeakAura packs are never copied by this addon."
	)
	PluginInstallFrame.Option1:Show()
	PluginInstallFrame.Option1:SetText("Apply Threat Plates")
	PluginInstallFrame.Option1:SetScript("OnClick", function() ns:ApplyThreatPlatesProfile(ns.db.mediaMode or "safe") end)
	PluginInstallFrame.Option2:Show()
	PluginInstallFrame.Option2:SetText("Install visual aura")
	PluginInstallFrame.Option2:SetScript("OnClick", function() ns:InstallWeakAuras() end)
end

local installer = {
	Title = "Lausudo Style Installation",
	Name = "Lausudo Style",
	Pages = { welcomePage, stylePage, integrationsPage },
	StepTitles = { "Privacy", "Style", "Integrations" },
	StepTitlesColor = { 0.72, 0.76, 0.80 },
	StepTitlesColorSelected = { 0.09, 0.52, 0.82 },
}

function ns:QueueInstaller()
	local pluginInstaller = E and E:GetModule("PluginInstaller", true)
	if not pluginInstaller or not pluginInstaller.Queue then
		self:Print("ElvUI's plugin installer is not ready.")
		return false
	end
	pluginInstaller:Queue(installer)
	return true
end

function ns:InstallWeakAuras()
	if not _G.LausudoVisualCore and LoadAddOn then LoadAddOn("LausudoVisualCore") end
	if _G.LausudoVisualCore and _G.LausudoVisualCore.Install then
		return _G.LausudoVisualCore:Install()
	end
	self:Print("Lausudo Visual Core and WeakAuras must both be enabled before installation.")
	return false
end

local function registerOptions()
	if not E or not E.Options or not E.Options.args then return end
	E.Options.args.lausudoStyle = {
		order = 100,
		type = "group",
		name = "Lausudo Style",
		args = {
			status = { order = 1, type = "description", name = function() return ns:GetStatusText() end },
			installer = { order = 2, type = "execute", name = "Open installer", func = function() ns:QueueInstaller() end },
			applySafe = { order = 3, type = "execute", name = "Apply safe style", func = function() ns:ApplyElvUIProfile("safe", false) end },
			applyPrivate = { order = 4, type = "execute", name = "Use detected private media", disabled = function() return not ns:DetectPrivateMedia().available end, func = function() ns:ApplyElvUIProfile("private", false) end },
			restore = { order = 5, type = "execute", name = "Restore previous profile", func = function() ns:RestoreElvUIProfile() end },
			cursor = { order = 6, type = "toggle", name = "Cursor halo", get = function() return ns.db.cursorEnabled end, set = function(_, value) ns:SetCursorEnabled(value) end },
		},
	}
end

local function handleSlash(message)
	local input = string.lower((message or ""):match("^%s*(.-)%s*$"))
	local command, argument, extra = input:match("^(%S*)%s*(%S*)%s*(%S*)$")
	if command == "install" then
		ns:QueueInstaller()
	elseif command == "apply" then
		local mode = argument == "private" and "private" or "safe"
		ns:ApplyElvUIProfile(mode, extra == "force" or argument == "force")
	elseif command == "restore" then
		ns:RestoreElvUIProfile()
		ns:RestoreThreatPlatesProfile()
	elseif command == "threatplates" then
		ns:ApplyThreatPlatesProfile(ns.db.mediaMode or "safe")
	elseif command == "weakauras" then
		ns:InstallWeakAuras()
	elseif command == "cursor" and (argument == "on" or argument == "off") then
		ns:SetCursorEnabled(argument == "on")
	else
		ns:Print(ns:GetStatusText())
		ns:Print("commands: /lausudostyle install, apply safe, apply private, restore, threatplates, weakauras, cursor on|off")
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	ns:EnsureDatabase()
	ns:CreateCursorHalo()
	SLASH_LAUSUDOSTYLE1 = "/lausudostyle"
	SlashCmdList.LAUSUDOSTYLE = handleSlash
	local pluginLibrary = LibStub and LibStub("LibElvUIPlugin-1.0", true)
	if pluginLibrary then pluginLibrary:RegisterPlugin(addonName, registerOptions) end
	ns:Print("loaded without changing profiles. Use /lausudostyle install when ready.")
end)
