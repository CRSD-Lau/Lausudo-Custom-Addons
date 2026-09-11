-- Author: Neil Mitchell
-- WoW 3.3.5a exposes bubble text, but no speaker/unit on the bubble frame.
-- Match chat events conservatively: unknown or conflicting speakers stay hidden.
local _, addon = ...
if not addon.compatible then return end
local driver = CreateFrame("Frame")
local roster, names, messages, bubbles = {}, {}, {}, {}
local grouped, enabled, ready = false, true, false
local revision, childCount, scanNeeded = 0, -1, true
local messageCount, nextPrune = 0, 0
local MESSAGE_TTL, MAX_MESSAGES = 120, 1024
local bubbleTexture = [[Interface\Tooltips\ChatBubble-Background]]

local function Normalize(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "{icon}")
    return (text:gsub("{([^}]+)}", function(tag)
        local lowerTag = tag:lower()
        if lowerTag:match("^rt[1-8]$") or (ICON_TAG_LIST and ICON_TAG_LIST[lowerTag]) then
            return "{icon}"
        end
        return "{" .. tag .. "}"
    end))
end

local function Allowed(text)
    if not enabled or not grouped or not addon.Style.ready then return false end
    local record = messages[Normalize(text)]
    if not record or record.blocked or record.expires <= GetTime() then return false end
    for guid in pairs(record.speakers) do
        if not roster[guid] then return false end
    end
    return next(record.speakers) ~= nil, record
end

local function RefreshBubble(frame, force)
    local state = bubbles[frame]
    if state.refreshing then return end
    local text = state.text:GetText()
    if not force and state.lastText == text and state.revision == revision then return end
    state.lastText, state.revision = text, revision
    local allowed, record = Allowed(text)
    local hidden = not allowed
    if allowed and (force or state.hidden or state.styledText ~= text
        or state.styledSender ~= record.sender or state.ambiguous ~= record.ambiguous) then
        state.refreshing = true
        addon.Style:Update(frame, record)
        state.refreshing = nil
        state.lastText = state.text:GetText()
        state.styledText, state.styledSender = state.lastText, record.sender
        state.ambiguous = record.ambiguous
    end
    if state.hidden ~= hidden then
        state.hidden = hidden
        frame:SetAlpha(hidden and 0 or state.alpha)
    elseif hidden and frame:GetAlpha() ~= 0 then
        frame:SetAlpha(0)
    end
end

local function TrackBubble(frame)
    if bubbles[frame] then return end
    local isBubble, text = frame.isSkinnedElvUI, frame.text
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region.GetTexture and region:GetTexture() == bubbleTexture then isBubble = true end
        if not text and region:IsObjectType("FontString") then text = region end
    end
    if not isBubble or not text then return end
    addon.Style:Skin(frame)
    text = frame.text or text
    local state = {text = text, alpha = frame:GetAlpha()}
    bubbles[frame] = state
    -- Native bubbles can be reused and the engine or a skin can change alpha.
    hooksecurefunc(frame, "SetAlpha", function(self, alpha)
        if state.writingAlpha then return end
        if alpha > 0 then state.alpha = alpha end
        if state.hidden and alpha ~= 0 then
            state.writingAlpha = true
            self:SetAlpha(0)
            state.writingAlpha = nil
        end
    end)
    hooksecurefunc(text, "SetText", function() RefreshBubble(frame, true) end)
    frame:HookScript("OnShow", function(self)
        state.alpha = 1
        RefreshBubble(self, true)
    end)
    RefreshBubble(frame, true)
end

local function Scan(...)
    for i = 1, select("#", ...) do TrackBubble(select(i, ...)) end
end

local function OnUpdate()
    local count = WorldFrame:GetNumChildren()
    if scanNeeded or childCount ~= count then
        scanNeeded, childCount = false, count
        Scan(WorldFrame:GetChildren())
    end
    local now = GetTime()
    if now >= nextPrune then
        nextPrune = now + 1
        for text, record in pairs(messages) do
            if record.expires <= now then
                messages[text] = nil
                messageCount = messageCount - 1
            end
        end
        revision = revision + 1
    end
    for frame in pairs(bubbles) do
        if frame:IsShown() then RefreshBubble(frame) end
    end
end

local function AddUnit(unit)
    local guid = UnitGUID(unit)
    local name, realm = UnitName(unit)
    if not guid or not name then return end
    roster[guid] = true
    if realm and realm ~= "" then
        names[name .. "-" .. realm:gsub("%s", "")] = guid
    else
        names[name] = guid
        local localRealm = GetRealmName()
        if localRealm then names[name .. "-" .. localRealm:gsub("%s", "")] = guid end
    end
end

local function UpdateRoster()
    wipe(roster)
    wipe(names)
    local raidCount, partyCount = GetNumRaidMembers(), GetNumPartyMembers()
    grouped = raidCount > 0 or partyCount > 0
    if grouped then
        AddUnit("player")
        if raidCount > 0 then
            for i = 1, raidCount do AddUnit("raid" .. i) end
        else
            for i = 1, partyCount do AddUnit("party" .. i) end
        end
    end
    revision, scanNeeded = revision + 1, true
    -- Leave chatBubblesParty and the chat window's messages untouched.
    local active = enabled and grouped and addon.Style.ready
    local value = active and "1" or "0"
    if GetCVar("chatBubbles") ~= value then SetCVar("chatBubbles", value) end
    driver:SetScript("OnUpdate", active and OnUpdate or nil)
    for frame in pairs(bubbles) do RefreshBubble(frame, true) end
    if not grouped or not enabled then
        wipe(messages)
        messageCount = 0
    end
end

local function RecordMessage(event, message, sender, guid)
    if not ready or not enabled or not grouped then return end
    local key = Normalize(message)
    if key == "" then return end
    local now = GetTime()
    local record = messages[key]
    if not record then
        -- Fail closed on cache pressure: an unrecorded message cannot show.
        if messageCount >= MAX_MESSAGES then return end
        record = {speakers = {}}
        messages[key] = record
        messageCount = messageCount + 1
    elseif record.expires <= now then
        record.speakers, record.blocked, record.ambiguous = {}, nil, nil
        record.guid, record.sender = nil, nil
    end
    record.expires = now + MESSAGE_TTL
    local identity
    if not event:find("MONSTER", 1, true) then
        -- A supplied GUID is authoritative; never trust a matching name over it.
        if guid and guid ~= "" then identity = guid else identity = names[sender] end
    end
    if identity and roster[identity] then
        if record.guid and record.guid ~= identity then record.ambiguous = true end
        record.speakers[identity] = true
        record.guid, record.sender = identity, sender
    else
        record.blocked = true
    end
    revision, scanNeeded = revision + 1, true
end

addon.StyleReady = function() if ready then UpdateRoster() end end

driver:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if type(LausudoGroupBubblesDB) ~= "table" then LausudoGroupBubblesDB = {} end
        enabled = LausudoGroupBubblesDB.enabled ~= false
        ready = true
        UpdateRoster()
    elseif event == "PLAYER_LOGOUT" then
        -- Keep the user's original off setting if this addon is later disabled.
        SetCVar("chatBubbles", "0")
        driver:SetScript("OnUpdate", nil)
    elseif event:find("CHAT_MSG_", 1, true) == 1 then
        RecordMessage(event, select(1, ...), select(2, ...), select(12, ...))
    elseif ready then
        UpdateRoster()
    end
end)

for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
    "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_NAME_UPDATE",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY"
}) do driver:RegisterEvent(event) end

SLASH_LAUSUDOGROUPBUBBLES1 = "/groupbubbles"
SlashCmdList.LAUSUDOGROUPBUBBLES = function(input)
    local command = (input or ""):lower():match("^%s*(.-)%s*$")
    if command == "on" or command == "off" then
        enabled = command == "on"
        LausudoGroupBubblesDB.enabled = enabled
        UpdateRoster()
    end
    DEFAULT_CHAT_FRAME:AddMessage("Group bubbles: " .. (enabled and "ON" or "OFF")
        .. (grouped and " (in a party/raid)." or " (solo; bubbles hidden).")
        .. " Commands: /groupbubbles on | off")
end
