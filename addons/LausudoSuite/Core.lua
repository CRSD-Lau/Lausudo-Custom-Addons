-- Author: Neil Mitchell
local addonName, suite = ...
local frame = CreateFrame("Frame")
local modules = {
    {"CrispFCT", "Crisp FCT", "/crispfct test"},
    {"WarmaneFontPack", "Font pack", "choose fonts in addon options"},
    {"TidyPlates_ThreatPlates", "Threat Plates", "/tptp"},
    {"LausudoGroupBubbles", "Group bubbles", "/groupbubbles"},
    {"LausudoHoPRange", "Paladin raid range", "/hoprange"},
    {"LausudoTankTargetThreat", "Tank target colors", "disable at character selection"},
}

function suite:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff1785d1Lausudo Suite:|r " .. message)
end

function suite:Status()
    self:Print("2.0.0-alpha.1 — optional modules; no profiles are applied automatically.")
    for _, module in ipairs(modules) do
        local _, title = GetAddOnInfo(module[1])
        local status = IsAddOnLoaded(module[1]) and "loaded" or (title and "installed, not loaded" or "not installed")
        self:Print(module[2] .. ": " .. status .. " (" .. module[3] .. ")")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    if type(LausudoSuiteDB) ~= "table" then LausudoSuiteDB = {} end
    suite.db = LausudoSuiteDB
    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_LAUSUDOSUITE1 = "/lausudo"
SlashCmdList.LAUSUDOSUITE = function(input)
    local command, target = (input or ""):lower():match("^%s*(%S*)%s*(%S*)%s*$")
    if command == "apply" or command == "restore" then
        if target ~= "elvui" and target ~= "nameplates" then
            suite:Print("Choose elvui or nameplates, for example /lausudo apply elvui.")
        else suite:Profile(target, command == "restore") end
    elseif command == "" or command == "status" then suite:Status()
    else suite:Print("/lausudo status | apply elvui | apply nameplates | restore elvui | restore nameplates") end
end
