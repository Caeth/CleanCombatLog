local _, CCL = ...
local CanAccess = CCL.CanAccess
local HISTORY_LIMIT = 160
local ROW_HEIGHT = 14
local OUTGOING_HEIGHT = 24
local justify = {"LEFT", "CENTER", "RIGHT"}
local schoolColors = {
    [1] = {1, 0.39, 0.39}, [2] = {1, 0.90, 0.50}, [4] = {1, 0.50, 0.20},
    [8] = {0.40, 0.85, 0.40}, [16] = {0.45, 0.80, 1},
    [32] = {0.72, 0.55, 1}, [64] = {0.89, 0.60, 1},
}

local events = {
    "COMBAT_LOG_MESSAGE", "COMBAT_TEXT_UPDATE", "UNIT_COMBAT", "UNIT_SPELLCAST_INTERRUPTED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
}

local results = {
    WOUND = "Hit", HEAL = "Heal", MISS = "Miss", DODGE = "Dodge",
    PARRY = "Parry", BLOCK = "Block", RESIST = "Resist", ABSORB = "Absorb",
    IMMUNE = "Immune", DEFLECT = "Deflect", EVADE = "Evade",
}

local auraEffects = {
    SPELL_AURA_START = "Buff gained",
    SPELL_AURA_END = "Buff faded",
    SPELL_AURA_START_HARMFUL = "Debuff gained",
    SPELL_AURA_END_HARMFUL = "Debuff faded",
}

local function Read(value, kind)
    if CanAccess(value) and type(value) == kind then return value end
end

local function MyActionsSelected()
    if CCL.Probe:IsFormatterExperimentActive() then return false end
    local filters = Read(Blizzard_CombatLog_Filters, "table")
    return filters ~= nil and Read(filters.currentFilter, "number") == 1
end

local function FilteredEventsEnabled()
    local query = C_CombatLog and C_CombatLog.AreFilteredEventsEnabled
    if not query then return false end
    local ok, enabled = pcall(query)
    return ok and Read(enabled, "boolean") == true
end

local function MyActionsReady()
    return MyActionsSelected() and FilteredEventsEnabled()
end

local function RefreshBackgroundFeed()
    local pane = CCL.personalFeedPane
    if InCombatLockdown() then return end
    local setter = C_CombatLog and C_CombatLog.SetFilteredEventsEnabled
    if not setter or (ChatFrame2 and ChatFrame2:IsVisible()) then return end
    if CleanCombatLogDB.personalFeedEnabled and CleanCombatLogDB.personalFeedBackground then
        if not MyActionsSelected() or FilteredEventsEnabled() then return end
        local ok = pcall(setter, true)
        pane.backgroundOwned = ok and FilteredEventsEnabled()
        pane.backgroundResult = pane.backgroundOwned and "enabled" or "unavailable"
    elseif pane.backgroundOwned then
        local ok = pcall(setter, false)
        if ok and not FilteredEventsEnabled() then
            pane.backgroundOwned, pane.backgroundResult = nil, nil
        end
    end
end

local hookedCombatLog
local function WatchCombatLog()
    if not ChatFrame2 or hookedCombatLog == ChatFrame2 then return end
    hookedCombatLog = ChatFrame2
    ChatFrame2:HookScript("OnHide", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshBackgroundFeed)
        else
            RefreshBackgroundFeed()
        end
    end)
end

local function RowAt(pane, offset)
    return pane.rows[(pane.latest - offset - 1) % HISTORY_LIMIT + 1]
end

local function MaximumOffset(pane, height)
    local used = 0
    for offset = pane.count - 1, 0, -1 do
        used = used + RowAt(pane, offset).height
        if used > height then return math.min(offset + 1, pane.count - 1) end
    end
    return 0
end

local function RenderHistory(pane)
    for _, row in ipairs(pane.rows) do row:Hide() end
    if pane.count == 0 then return end
    local height = pane:GetHeight()
    pane.offset = math.min(pane.offset, MaximumOffset(pane, height))
    local used = 0
    for offset = pane.offset, pane.count - 1 do
        local row = RowAt(pane, offset)
        if used > 0 and used + row.height > height then break end
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", pane.starts[row.column] + 3, used)
        row:SetWidth(math.max(1, pane.widths[row.column] - 6))
        row:Show()
        used = used + row.height
    end
end

function CCL:SetPersonalFeedColumnWidths(incoming, effects, outgoing, gap)
    local pane = self.personalFeedPane
    pane.starts = {0, incoming + gap, incoming + effects + 2 * gap}
    pane.widths = {incoming, effects, outgoing}
    RenderHistory(pane)
end

function CCL:AddPersonalFeedRow(column, value, red, green, blue, tooltip, fallback)
    local pane = self.personalFeedPane
    if not self.personalFeedVisible or not justify[column] then return end
    local slot = pane.latest % HISTORY_LIMIT + 1
    local row = pane.rows[slot]
    if not row then
        row = CreateFrame("Frame", nil, pane)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetAllPoints()
        row.text:SetJustifyV("MIDDLE")
        row.text:SetWordWrap(true)
        row:SetScript("OnEnter", function(frame)
            if not frame.tooltip then return end
            GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
            GameTooltip:SetText(frame.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pane.rows[slot] = row
    end

    -- Protected values go directly to the native text setter.
    local ok = pcall(row.text.SetText, row.text, value)
    if not ok then
        if not fallback then
            if pane.count < HISTORY_LIMIT then row:Hide() end
            return false
        end
        row.text:SetText(fallback)
    end
    row.column, row.tooltip = column, tooltip
    row.height = column == 3 and OUTGOING_HEIGHT or ROW_HEIGHT
    row:SetHeight(row.height)
    row:EnableMouse(tooltip ~= nil)
    row.text:SetJustifyH(justify[column])
    row.text:SetTextColor(Read(red, "number") or 1, Read(green, "number") or 1, Read(blue, "number") or 1)
    pane.latest = slot
    pane.count = math.min(HISTORY_LIMIT, pane.count + 1)
    if pane.offset > 0 then pane.offset = pane.offset + 1 end
    RenderHistory(pane)
    return ok
end

local function OwnUnit(value)
    local unit = Read(value, "string")
    if unit == "player" or unit == "pet" then return unit end
end

local function AddIncomingAmount(label, amountValue, action, schoolMask)
    local amount = Read(amountValue, "number")
    local color = action == "HEAL" and CCL.COLORS.lightgreen
        or action == "WOUND" and CCL.COLORS.red or CCL.COLORS.beige
    local fallback = color .. label .. CCL.COLORS.reset
    local protected = (action == "WOUND" or action == "HEAL") and not CanAccess(amountValue)
    local showAmount = protected or (amount and amount > 0)
    local red, green, blue = 1, 1, 1
    local healing = action == "HEAL"
    if healing then
        red, green, blue = 0.49, 0.80, 0.43
    elseif action == "WOUND" then
        red, green, blue = unpack(schoolColors[Read(schoolMask, "number")] or schoolColors[1])
    end
    local value = fallback
    if showAmount then value = amountValue end
    local ok = CCL:AddPersonalFeedRow(healing and 2 or 1, value, red, green, blue,
        showAmount and label or nil, fallback)
    if protected then
        local pane = CCL.personalFeedPane
        local counter = ok and "amountsAccepted" or "amountErrors"
        pane[counter] = pane[counter] + 1
    end
end

local function AddIncoming(unitValue, actionValue, flagValue, amountValue, schoolMask)
    local unit = OwnUnit(unitValue)
    local action = Read(actionValue, "string")
    local label = results[action]
    if not unit or not label then return end
    if Read(flagValue, "string") == "CRITICAL" then label = label .. " •" end
    if unit == "pet" then label = "Pet " .. label end
    AddIncomingAmount(label, amountValue, action, schoolMask)
end

local function AddCombatTextEvent(eventType)
    eventType = Read(eventType, "string")
    local effect = auraEffects[eventType]
    if not effect or not C_CombatText or not C_CombatText.GetCurrentEventInfo
        or not C_CombatText.GetActiveUnit then return end
    local unitOK, unit = pcall(C_CombatText.GetActiveUnit)
    if not unitOK or Read(unit, "string") ~= "player" then return end
    local ok, value = pcall(C_CombatText.GetCurrentEventInfo)
    if not ok then return end
    local name = Read(value, "string")
    local harmful = eventType == "SPELL_AURA_START_HARMFUL" or eventType == "SPELL_AURA_END_HARMFUL"
    CCL:AddRow(2, (harmful and CCL.COLORS.red or CCL.COLORS.lightgreen) .. effect .. CCL.COLORS.reset, name)
end

local function OnEvent(listener, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        listener.live = MyActionsReady()
    elseif event == "PLAYER_REGEN_ENABLED" then
        listener.live = false
        RefreshBackgroundFeed()
    elseif event == "PLAYER_ENTERING_WORLD" then
        WatchCombatLog()
        RefreshBackgroundFeed()
    elseif event == "COMBAT_LOG_MESSAGE" then
        if not listener.live then return end
        if not MyActionsReady() then
            listener.live = false
            return
        end
        if not CCL.personalFeedVisible then CCL:SetPersonalFeedVisible(true) end
        local message, red, green, blue = ...
        local pane = CCL.personalFeedPane
        local counter = CCL:AddPersonalFeedRow(3, message, red, green, blue) and "messagesAccepted" or "errors"
        pane[counter] = pane[counter] + 1
    else
        if CCL:IsPlayerCombatAdapterEnabled()
            or CCL.CombatLog:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then return end
        if event == "UNIT_COMBAT" then
            AddIncoming(...)
        elseif event == "COMBAT_TEXT_UPDATE" then
            AddCombatTextEvent(...)
        else
            local unit = OwnUnit(...)
            if unit then
                CCL:AddRow(2, CCL.COLORS.beige .. (unit == "pet" and "Pet interrupted" or "Interrupted")
                    .. CCL.COLORS.reset)
            end
        end
    end
end

local function SetEnabled(enabled)
    local listener = CCL.personalFeedListener
    local pane = CCL.personalFeedPane
    listener:UnregisterAllEvents()
    listener.live = false
    CCL:ClearSecretRows()
    pane.messageRegistered = false
    if enabled then
        for _, event in ipairs(events) do
            pcall(listener.RegisterEvent, listener, event)
        end
        pane.messageRegistered = listener:IsEventRegistered("COMBAT_LOG_MESSAGE")
    end
    CleanCombatLogDB.personalFeedEnabled = enabled
    CCL:SetPersonalFeedVisible(enabled)
    WatchCombatLog()
    RefreshBackgroundFeed()
end

function CCL:InitializePersonalFeed()
    local pane = CreateFrame("Frame", nil, self.frame)
    pane:SetPoint("TOPLEFT", self.columns[1], "TOPLEFT")
    pane:SetPoint("BOTTOMRIGHT", self.columns[3], "BOTTOMRIGHT")
    pane.rows, pane.latest, pane.count, pane.offset, pane.errors = {}, 0, 0, 0, 0
    pane.amountsAccepted, pane.amountErrors = 0, 0
    pane.messagesAccepted = 0
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function(frame, delta)
        if IsShiftKeyDown() then
            frame.offset = delta > 0 and frame.count or 0
        else
            frame.offset = math.max(0, frame.offset + (delta > 0 and 1 or -1))
        end
        RenderHistory(frame)
    end)
    pane:SetScript("OnSizeChanged", RenderHistory)
    local listener = CreateFrame("Frame")
    listener:SetScript("OnEvent", OnEvent)
    self.personalFeedPane, self.personalFeedListener = pane, listener
    local enabled = CleanCombatLogDB.personalFeedEnabled
    if enabled == nil then enabled = self:IsForeverClient() end
    SetEnabled(enabled)
end

function CCL:ClearPersonalFeed()
    local pane = self.personalFeedPane
    if not pane then return end
    for _, row in ipairs(pane.rows) do
        row.text:SetText("")
        row:Hide()
    end
    pane.latest, pane.count, pane.offset, pane.errors = 0, 0, 0, 0
    pane.amountsAccepted, pane.amountErrors = 0, 0
    pane.messagesAccepted = 0
end

function CCL:GetPersonalFeedDiagnostics()
    local pane = self.personalFeedPane
    local activeUnit
    if C_CombatText and C_CombatText.GetActiveUnit then
        local ok, unit = pcall(C_CombatText.GetActiveUnit)
        if ok then activeUnit = Read(unit, "string") end
    end
    return {
        enabled = CleanCombatLogDB.personalFeedEnabled,
        myActionsReady = MyActionsReady(),
        background = CleanCombatLogDB.personalFeedBackground or false,
        combatLogVisible = ChatFrame2 and ChatFrame2:IsVisible() or false,
        filteredEvents = FilteredEventsEnabled(),
        backgroundResult = pane.backgroundResult or "not attempted",
        combatTextUnit = activeUnit or "unavailable",
        messagesAccepted = pane.messagesAccepted,
        messageErrors = pane.errors,
        amountsAccepted = pane.amountsAccepted,
        amountErrors = pane.amountErrors,
    }
end

function CCL:HandlePersonalFeedCommand(rest)
    local action = rest:lower()
    if action == "background on" or action == "background off" then
        if InCombatLockdown() then
            self.Print("Leave combat before changing background collection.")
            return
        end
        CleanCombatLogDB.personalFeedBackground = action == "background on"
        RefreshBackgroundFeed()
    elseif action == "on" or action == "off" then
        if InCombatLockdown() then
            self.Print("Leave combat before changing the personal feed.")
            return
        end
        SetEnabled(action == "on")
    elseif action ~= "" and action ~= "status" then
        self.Print("Use /ccl feed [on|off|status|background on|background off].")
        return
    end
    local pane = self.personalFeedPane
    local ready = MyActionsReady()
    self.Print("Personal feed", CleanCombatLogDB.personalFeedEnabled and "on" or "off",
        "· My Actions ready", ready and "yes" or "no",
        "· message event registered", pane.messageRegistered and "yes" or "no",
        "· timeline rows", pane.count, "· render errors", pane.errors)
    self.Print("Background collection", CleanCombatLogDB.personalFeedBackground and "on" or "off",
        "· filtered events", FilteredEventsEnabled() and "enabled" or "disabled",
        "· last activation", pane.backgroundResult or "not attempted")
    self.Print("Protected incoming amounts accepted", pane.amountsAccepted,
        "· amount render errors", pane.amountErrors)
    if CleanCombatLogDB.personalFeedEnabled and not ready then
        self.Print("Select My Actions before combat. For a hidden log, try /ccl feed background on.")
    end
end
