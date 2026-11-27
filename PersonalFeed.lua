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
local schoolNames = {
    [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature",
    [16] = "Frost", [32] = "Shadow", [64] = "Arcane",
}

local events = {
    "COMBAT_LOG_MESSAGE", "COMBAT_TEXT_UPDATE", "UNIT_COMBAT", "UNIT_SPELLCAST_INTERRUPTED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
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

local function Timestamp()
    return date("%H:%M:%S")
end

local function ShowRowTooltip(row)
    if row.fullTextReady then
        row.fullText:Show()
    elseif row.tooltip then
        GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
        GameTooltip:SetText(row.tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

local function HideRowTooltip(row)
    if row.fullText then row.fullText:Hide() end
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function SetOutgoingTooltip(row, value, red, green, blue)
    if not row.fullText then
        local preview = CreateFrame("Frame", nil, UIParent)
        preview:SetFrameStrata("TOOLTIP")
        preview:SetClampedToScreen(true)
        preview:SetSize(440, 80)
        preview:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 4)
        local background = preview:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.04, 0.04, 0.05, 0.94)
        local timestamp = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timestamp:SetPoint("TOPLEFT", 9, -7)
        local content = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        content:SetPoint("TOPLEFT", 9, -22)
        content:SetPoint("BOTTOMRIGHT", -9, 7)
        content:SetJustifyH("LEFT")
        content:SetJustifyV("TOP")
        content:SetWordWrap(true)
        preview.text, preview.timestamp = content, timestamp
        preview:Hide()
        row.fullText = preview
    end
    local text = row.fullText.text
    row.fullTextReady = pcall(text.SetText, text, value)
    row.fullText.timestamp:SetText(Timestamp())
    text:SetTextColor(red, green, blue)
end

local function MyActionsSelected()
    if CCL.Probe:IsFormatterExperimentActive() then return false end
    local container = Read(Blizzard_CombatLog_Filters, "table")
    return container ~= nil and Read(container.currentFilter, "number") == 1
end

local function DescribeMyActionsOptions()
    if not MyActionsSelected() then return end
    local profiles = Read(Blizzard_CombatLog_Filters.filters, "table")
    local profile = profiles and Read(profiles[1], "table")
    if not profile then return end
    local settings = Read(profile.settings, "table")
    local rules = Read(profile.filters, "table")
    local destinations, auras
    if rules then
        for _, value in ipairs(rules) do
            local rule = Read(value, "table")
            local flags = rule and Read(rule.destFlags, "table")
            if flags then
                for _, enabled in pairs(flags) do
                    if Read(enabled, "boolean") then destinations = true end
                end
            end
            local eventList = rule and Read(rule.eventList, "table")
            if eventList and (Read(eventList.SPELL_AURA_APPLIED, "boolean")
                or Read(eventList.SPELL_AURA_REMOVED, "boolean")) then
                auras = true
            end
        end
    end
    return destinations, settings and Read(settings.timestamp, "boolean"), auras
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
    if pane.count == 0 then return end
    local visible = {}
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
        visible[row] = true
        used = used + row.height
    end
    for row in pairs(pane.visibleRows) do
        if not visible[row] then row:Hide() end
    end
    pane.visibleRows = visible
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
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", HideRowTooltip)
        row:SetScript("OnHide", HideRowTooltip)
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
    HideRowTooltip(row)
    row.column, row.tooltip, row.fullTextReady = column, tooltip, false
    row.height = column == 3 and OUTGOING_HEIGHT or ROW_HEIGHT
    row:SetHeight(row.height)
    row.text:SetJustifyH(justify[column])
    red, green, blue = Read(red, "number") or 1, Read(green, "number") or 1, Read(blue, "number") or 1
    row.text:SetTextColor(red, green, blue)
    if column == 3 and ok and not tooltip then SetOutgoingTooltip(row, value, red, green, blue) end
    row:EnableMouse(tooltip ~= nil or row.fullTextReady)
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

local function AddIncomingAmount(label, amountValue, action, schoolMask, unit, flag)
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
    local school = schoolNames[Read(schoolMask, "number")]
    local tooltip = Timestamp() .. "  " .. label .. "\nRecipient: " .. (unit == "pet" and "Pet" or "You")
    if amount then tooltip = tooltip .. "\nAmount: " .. amount end
    if action == "WOUND" and school then tooltip = tooltip .. "\nSchool: " .. school end
    if flag and flag ~= "" then tooltip = tooltip .. "\nResult: " .. flag end
    local ok = CCL:AddPersonalFeedRow(healing and 2 or 1, value, red, green, blue, tooltip, fallback)
    if unit == "player" and (action == "WOUND" or healing) then
        local recent = CCL.personalFeedPane.recentIncoming
        if #recent == 5 then table.remove(recent, 1) end
        recent[#recent + 1] = Timestamp() .. "  " .. label .. (amount and ("  " .. amount) or "")
    end
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
    local flag = Read(flagValue, "string")
    if flag == "CRITICAL" then label = label .. " •" end
    if unit == "pet" then label = "Pet " .. label end
    AddIncomingAmount(label, amountValue, action, schoolMask, unit, flag)
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

local function GetPersonalMeterTotal(metric)
    local query = C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
    if not query then return end
    local current = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, value = pcall(query, current, metric)
    local session = ok and Read(value, "table")
    local sources = session and Read(session.combatSources, "table")
    if not sources then return end
    for _, entry in ipairs(sources) do
        local source = Read(entry, "table")
        if source and Read(source.isLocalPlayer, "boolean") then
            return Read(source.totalAmount, "number")
        end
    end
end

local function AddCombatSummary(listener, duration)
    local ended = listener.combatSequence
    local function Finish()
        if listener.combatSequence ~= ended or InCombatLockdown() or not CCL.personalFeedVisible then return end
        local lines = {string.format("Combat duration: %d:%02d", math.floor(duration / 60), math.floor(duration % 60))}
        local damage, taken, healing = GetPersonalMeterTotal(0), GetPersonalMeterTotal(7), GetPersonalMeterTotal(2)
        if damage or taken or healing then
            lines[#lines + 1] = "Damage Meter · current session"
            if damage then lines[#lines + 1] = "Damage done: " .. damage end
            if taken then lines[#lines + 1] = "Damage taken: " .. taken end
            if healing then lines[#lines + 1] = "Healing done: " .. healing end
        end
        CCL:AddRow(2, "Combat summary", table.concat(lines, "\n"))
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.25, Finish) else Finish() end
end

local function AddDeathRecap()
    local lines = {Timestamp() .. "  You died"}
    local query = C_DeathRecap and C_DeathRecap.GetRecapEvents
    if query then
        local ok, value = pcall(query)
        local entries = ok and Read(value, "table")
        if entries then
            for index = 1, math.min(5, #entries) do
                local entry = Read(entries[index], "table")
                if entry then
                    local source = Read(entry.sourceName, "string")
                    local ability = Read(entry.spellName, "string")
                    local amount = Read(entry.amount, "number")
                    if source or ability or amount then
                        local parts = {}
                        if source then parts[#parts + 1] = source end
                        if ability then parts[#parts + 1] = ability end
                        if amount then parts[#parts + 1] = amount end
                        lines[#lines + 1] = table.concat(parts, " · ")
                    end
                end
            end
        end
    end
    if #lines == 1 then
        local recent = CCL.personalFeedPane.recentIncoming
        if #recent > 0 then lines[#lines + 1] = "Recent incoming results" end
        for index = #recent, 1, -1 do lines[#lines + 1] = recent[index] end
    end
    CCL:AddRow(2, CCL.COLORS.beige .. "†† You died ††" .. CCL.COLORS.reset, table.concat(lines, "\n"))
end

local function OnEvent(listener, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        listener.live = MyActionsReady()
        listener.combatSequence = (listener.combatSequence or 0) + 1
        listener.combatStarted = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        listener.live = false
        RefreshBackgroundFeed()
        if listener.combatStarted then
            AddCombatSummary(listener, GetTime() - listener.combatStarted)
            listener.combatStarted = nil
        end
    elseif event == "PLAYER_DEAD" then
        AddDeathRecap()
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
    listener.combatStarted = nil
    listener.combatSequence = (listener.combatSequence or 0) + 1
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
    pane.recentIncoming, pane.visibleRows = {}, {}
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
        if row.fullText then row.fullText.text:SetText("") end
        row:Hide()
    end
    pane.latest, pane.count, pane.offset, pane.errors = 0, 0, 0, 0
    pane.amountsAccepted, pane.amountErrors = 0, 0
    pane.messagesAccepted = 0
    pane.recentIncoming, pane.visibleRows = {}, {}
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
    local destinations, timestamps, auras = DescribeMyActionsOptions()
    if destinations then
        self.Print("My Actions includes Done To entries. Clear Done To in Combat Log settings to keep incoming rows out of Outgoing.")
    end
    if timestamps or auras then
        self.Print("For a compact Outgoing column, turn off "
            .. (timestamps and "Show Timestamp" or "") .. (timestamps and auras and " and " or "")
            .. (auras and "Auras" or "") .. " in My Actions.")
    end
    if CleanCombatLogDB.personalFeedEnabled and not ready then
        self.Print("Select My Actions before combat. For a hidden log, try /ccl feed background on.")
    end
end
