-- Author: Neil Mitchell
local _, addon = ...
local E = ElvUI and ElvUI[1]
local M = E and E.GetModule and E:GetModule("Misc", true)
addon.compatible = M and type(M.SkinBubble) == "function"
    and type(M.UpdateBubbleBorder) == "function" and type(M.AddChatBubbleName) == "function"
    and type(E.NewModule) == "function" and type(E.RegisterModule) == "function"
if not addon.compatible then
    DEFAULT_CHAT_FRAME:AddMessage("Lausudo Group Bubbles: unsupported ElvUI bubble API; module inactive.")
    return
end
local Style = E:NewModule("LausudoGroupBubblesStyle")
addon.Style = Style

function Style:Initialize()
    local general = E.private.general
    if general.chatBubbles == "disabled" then general.chatBubbles = "backdrop" end
    -- Respect the recipient's font; the suite never requires private media.
    if not general.chatBubbleFont then general.chatBubbleFont = "PT Sans Narrow Bold" end
    -- Preserve the saved 12-point size, outline, and speaker-name preference.
    -- This addon supplies discovery/events; avoid a second ElvUI polling loop
    -- and its unbounded message-to-speaker caches.
    if M.BubbleFrame then
        M.BubbleFrame:UnregisterAllEvents()
        M.BubbleFrame:SetScript("OnUpdate", nil)
        M.BubbleFrame:SetScript("OnEvent", nil)
    end
    self.ready = true
    if addon.StyleReady then addon.StyleReady() end
end

function Style:Skin(frame)
    if not frame.isSkinnedElvUI then M:SkinBubble(frame) end
end

function Style:Update(frame, record)
    -- Use the installed ElvUI code for backdrop, border, class mentions and
    -- raid icons. Our bounded, roster-checked cache supplies the speaker name.
    M.UpdateBubbleBorder(frame)
    if record and not record.ambiguous and frame.Name and E.private.general.chatBubbleName then
        local guid = record.guid
        local _, class = GetPlayerInfoByGUID(guid)
        if not class or not RAID_CLASS_COLORS[class] then guid = nil end
        M:AddChatBubbleName(frame, guid, record.sender)
    end
end

E:RegisterModule(Style:GetName())
