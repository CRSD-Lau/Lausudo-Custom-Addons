-- Author: Neil Mitchell
local _, suite = ...
local marker = "LausudoSuite:1"

local function merge(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            merge(target[key], value)
        else target[key] = value end
    end
end

local function adapter(kind)
    if kind == "elvui" then
        local E = _G.ElvUI and _G.ElvUI[1]
        if E and E.data and E.UpdateAll then
            return E.data, function() E:UpdateAll(true) end
        end
    elseif kind == "nameplates" then
        local threat = _G.TidyPlatesThreat
        if threat and threat.db and threat.ConfigRefresh then
            return threat.db, function() threat:ConfigRefresh() end
        end
    end
end

local function profiles(database)
    return database.profiles or (database.sv and database.sv.profiles) or {}
end

local function hasProfile(database, name)
    for _, candidate in ipairs(database:GetProfiles({})) do
        if candidate == name then return true end
    end
    return false
end

local function preset(kind)
    local font = "Friz Quadrata TT"
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media and media:Fetch("font", "PT Sans Narrow Bold", true) then
        font = "PT Sans Narrow Bold"
    end
    if kind == "elvui" then
        -- A portable visual baseline. Layout, bindings and character settings
        -- are inherited locally from the recipient's current profile.
        return {
            general = {font = font, fontSize = 12, fontStyle = "OUTLINE",
                backdropcolor = {r = 0.035, g = 0.045, b = 0.055},
                bordercolor = {r = 0.12, g = 0.15, b = 0.18},
                valuecolor = {r = 0.09, g = 0.52, b = 0.82}},
            unitframe = {font = font, fontSize = 12, fontOutline = "OUTLINE"},
            actionbar = {font = font, fontSize = 11, fontOutline = "OUTLINE"},
            tooltip = {font = font, fontSize = 11, fontOutline = "OUTLINE"},
        }
    end
    return {settings = {
        healthbar = {texture = "ThreatPlatesBar", width = 130, height = 10},
        name = {typeface = font, size = 15, flags = "OUTLINE", shadow = true},
        level = {typeface = font, size = 12, flags = "OUTLINE", shadow = true},
        spelltext = {typeface = font, size = 12, flags = "OUTLINE", shadow = true},
    }}
end

function suite:Profile(kind, restore)
    if InCombatLockdown() then self:Print("Leave combat before changing profiles."); return false end
    local database, refresh = adapter(kind)
    if not database or type(database.GetCurrentProfile) ~= "function" or type(database.GetProfiles) ~= "function"
        or type(database.SetProfile) ~= "function" or type(database.CopyProfile) ~= "function" then
        self:Print("That addon is unavailable or its profile API is unsupported."); return false
    end
    local state = type(self.db[kind]) == "table" and self.db[kind] or {}
    if restore then
        if not state.previous or not hasProfile(database, state.previous) then
            self:Print("The previous profile is unavailable. Choose one in the addon's profile menu."); return false
        end
        local ok = pcall(function() database:SetProfile(state.previous); refresh() end)
        self:Print(ok and "Previous profile restored." or "Restore failed; use the addon's profile menu.")
        return ok
    end
    local current = database:GetCurrentProfile()
    if current == state.owned and profiles(database)[current]
        and profiles(database)[current].lausudoSuiteOwner == marker then
        self:Print("Your suite profile is already active; customizations were kept."); return true
    end
    -- Each character gets an independent profile, even on a shared account.
    -- These names exist only in the recipient's local SavedVariables.
    local base = "Lausudo Suite - " .. UnitName("player") .. " - " .. GetRealmName()
    local name, suffix = state.owned, 2
    if not name or not profiles(database)[name] or profiles(database)[name].lausudoSuiteOwner ~= marker then
        name = base
        while hasProfile(database, name) do name = base .. " " .. suffix; suffix = suffix + 1 end
    end
    local create = not hasProfile(database, name)
    local ok = pcall(function()
        database:SetProfile(name)
        if create then
            database:CopyProfile(current)
            merge(database.profile, preset(kind))
            database.profile.lausudoSuiteOwner = marker
        end
        refresh()
    end)
    if not ok then
        pcall(function() database:SetProfile(current); refresh() end)
        -- Remove only the new, failed profile to avoid accumulating leftovers.
        if create and database.DeleteProfile then pcall(database.DeleteProfile, database, name, true) end
        self:Print("Apply failed; attempted to restore your previous profile. Check the addon's profile menu.")
        return false
    end
    self.db[kind] = {owned = name, previous = current}
    self:Print("Suite profile selected. Use /lausudo restore " .. kind .. " to go back.")
    return true
end
