local _, CCL = ...
local CanAccess = CCL.CanAccess
local HISTORY_LIMIT = 160
local ROW_HEIGHT = 27

local events = {
    "COMBAT_LOG_MESSAGE", "COMBAT_TEXT_UPDATE", "UNIT_COMBAT", "UNIT_SPELLCAST_INTERRUPTED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local results = {
    WOUND = "Hit", HEAL = "Heal", MISS = "Miss", DODGE = "Dodge",
    PARRY = "Parry", BLOCK = "Block", RESIST = "Resist", ABSORB = "Absorb",
    IMMUNE = "Immune", DEFLECT = "Deflect", EVADE = "Evade",
}

local spellDamage = {
    SPELL_DAMAGE = "Spell hit",
    SPELL_DAMAGE_CRIT = "Spell hit •",
    SPELL_PERIODIC_DAMAGE = "Tick",
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

local function MyActionsReady()
    if CCL.Probe:IsFormatterExperimentActive() then return false end
    local filters = Read(Blizzard_CombatLog_Filters, "table")
    if not filters or Read(filters.currentFilter, "number") ~= 1 then return false end
    if not ChatFrame2 or not ChatFrame2:IsVisible() then return false end
    local query = C_CombatLog and C_CombatLog.AreFilteredEventsEnabled
    if not query then return false end
    local ok, enabled = pcall(query)
    return ok and Read(enabled, "boolean") == true
end

local function RenderHistory(pane)
    for _, row in ipairs(pane.rows) do row:Hide() end
    if pane.count == 0 then return end
    local visible = math.max(1, math.floor(pane:GetHeight() / ROW_HEIGHT))
    pane.offset = math.min(pane.offset, math.max(0, pane.count - visible))
    for index = 0, math.min(visible, pane.count - pane.offset) - 1 do
        local slot = (pane.latest - pane.offset - index - 1) % HISTORY_LIMIT + 1
        local row = pane.rows[slot]
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 2, index * ROW_HEIGHT)
        row:SetPoint("RIGHT", pane, "RIGHT", -2, 0)
        row:Show()
    end
end

local function AddMessage(pane, message, red, green, blue)
    local slot = pane.latest % HISTORY_LIMIT + 1
    local row = pane.rows[slot]
    if not row then
        row = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetHeight(ROW_HEIGHT)
        row:SetJustifyH("LEFT")
        row:SetJustifyV("BOTTOM")
        row:SetWordWrap(true)
        pane.rows[slot] = row
    end

    -- The client supplies the formatted value directly to the UI.
    if not pcall(row.SetText, row, message) then
        pane.errors = pane.errors + 1
        -- A failed setter may leave this slot unchanged. Keep the history indices intact.
        if pane.count < HISTORY_LIMIT then row:Hide() end
        return false
    end
    red, green, blue = Read(red, "number"), Read(green, "number"), Read(blue, "number")
    if red and green and blue then
        row:SetTextColor(red, green, blue)
    else
        row:SetTextColor(1, 1, 1)
    end
    pane.latest = slot
    pane.messagesAccepted = pane.messagesAccepted + 1
    pane.count = math.min(HISTORY_LIMIT, pane.count + 1)
    if pane.offset > 0 then pane.offset = pane.offset + 1 end
    RenderHistory(pane)
    return true
end

local function OwnUnit(value)
    local unit = Read(value, "string")
    if unit == "player" or unit == "pet" then return unit end
end

local function AddIncomingAmount(label, amountValue, action)
    local amount = Read(amountValue, "number")
    local color = action == "HEAL" and CCL.COLORS.lightgreen
        or action == "WOUND" and CCL.COLORS.red or CCL.COLORS.beige
    local prefix = color .. label .. CCL.COLORS.reset
    local protected = (action == "WOUND" or action == "HEAL") and not CanAccess(amountValue)
    local showAmount = protected or (amount and amount > 0)
    local heal = action == "HEAL" and showAmount
    local red, green, blue = 1, 1, 1
    local valuePrefix = prefix
    if heal then
        red, green, blue = 0.49, 0.80, 0.43
        valuePrefix = ""
    end
    local value = ""
    if protected then
        value = amountValue
    elseif showAmount then
        value = amount
    end
    local ok = CCL:AddSecretValueRow(1, value, red, green, blue, valuePrefix, nil, prefix)
    if protected then
        local pane = CCL.personalFeedPane
        local counter = ok and "amountsAccepted" or "amountErrors"
        pane[counter] = pane[counter] + 1
    end
end

local function AddIncoming(unitValue, actionValue, flagValue, amountValue)
    local unit = OwnUnit(unitValue)
    local action = Read(actionValue, "string")
    local label = results[action]
    if not unit or not label then return end
    if Read(flagValue, "string") == "CRITICAL" then label = label .. " •" end
    if unit == "pet" then label = "Pet " .. label end
    AddIncomingAmount(label, amountValue, action)
end

local function AddCombatTextEvent(eventType)
    eventType = Read(eventType, "string")
    local damage, effect = spellDamage[eventType], auraEffects[eventType]
    if not (damage or effect) or not C_CombatText or not C_CombatText.GetCurrentEventInfo
        or not C_CombatText.GetActiveUnit then return end
    local unitOK, unit = pcall(C_CombatText.GetActiveUnit)
    if not unitOK or Read(unit, "string") ~= "player" then return end
    local ok, value = pcall(C_CombatText.GetCurrentEventInfo)
    if not ok then return end
    if damage then
        local pane = CCL.personalFeedPane
        pane.spellRows = pane.spellRows + 1
        AddIncomingAmount(damage, value, "WOUND")
    else
        local name = Read(value, "string")
        local color = eventType == "SPELL_AURA_START_HARMFUL" or eventType == "SPELL_AURA_END_HARMFUL"
        CCL:AddRow(2, (color and CCL.COLORS.red or CCL.COLORS.lightgreen) .. effect .. CCL.COLORS.reset, name)
    end
end

local function OnEvent(listener, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        listener.live = MyActionsReady()
    elseif event == "PLAYER_REGEN_ENABLED" then
        listener.live = false
    elseif event == "COMBAT_LOG_MESSAGE" then
        if not listener.live then return end
        if not MyActionsReady() then
            listener.live = false
            return
        end
        if AddMessage(CCL.personalFeedPane, ...) and not CCL.personalFeedVisible then
            CCL:SetPersonalFeedVisible(true)
        end
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
end

function CCL:InitializePersonalFeed()
    local pane = CreateFrame("Frame", nil, self.frame)
    pane:SetAllPoints(self.columns[3])
    pane.rows, pane.latest, pane.count, pane.offset, pane.errors = {}, 0, 0, 0, 0
    pane.amountsAccepted, pane.amountErrors, pane.spellRows = 0, 0, 0
    pane.messagesAccepted = 0
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function(frame, delta)
        frame.offset = math.max(0, frame.offset + (delta > 0 and 1 or -1))
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
        row:SetText("")
        row:Hide()
    end
    pane.latest, pane.count, pane.offset, pane.errors = 0, 0, 0, 0
    pane.amountsAccepted, pane.amountErrors, pane.spellRows = 0, 0, 0
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
        combatTextUnit = activeUnit or "unavailable",
        messagesAccepted = pane.messagesAccepted,
        messageErrors = pane.errors,
        spellRows = pane.spellRows,
        amountsAccepted = pane.amountsAccepted,
        amountErrors = pane.amountErrors,
    }
end

function CCL:HandlePersonalFeedCommand(rest)
    local action = rest:lower()
    if action == "on" or action == "off" then
        SetEnabled(action == "on")
    elseif action ~= "" and action ~= "status" then
        self.Print("Use /ccl feed [on|off|status].")
        return
    end
    local pane = self.personalFeedPane
    local ready = MyActionsReady()
    self.Print("Personal feed", CleanCombatLogDB.personalFeedEnabled and "on" or "off",
        "· My Actions ready", ready and "yes" or "no",
        "· message event registered", pane.messageRegistered and "yes" or "no",
        "· retained lines", pane.count, "· render errors", pane.errors)
    self.Print("Protected incoming amounts accepted", pane.amountsAccepted,
        "· amount render errors", pane.amountErrors, "· Combat Text spell rows", pane.spellRows)
    if CleanCombatLogDB.personalFeedEnabled and not ready then
        self.Print("Open Blizzard's Combat Log and select My Actions before combat.")
    end
end
