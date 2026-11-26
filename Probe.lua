local addonName, CCL = ...

local frame = CreateFrame("Frame")
CCL.Probe = frame

local active, startedAt, combatTextUnit = false, 0, nil
local records, counts, registration = {}, {}, {}
local formatterRestoreSettings, formatterRestoreFilteredEvents, formatterProfile
local formatterPreview, formatterPreviewRows, formatterPreviewIndex
local MAX_RECORDS = 2500
local nextID, phase, refilterUntil = 0, 0, 0
local units, auraSnapshots = {}, {}
local comparisonStart

local EVENTS = {
    "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "COMBAT_LOG_MESSAGE", "COMBAT_LOG_APPLY_FILTER_SETTINGS", "COMBAT_LOG_REFILTER_ENTRIES",
    "COMBAT_TEXT_UPDATE",
    "UNIT_COMBAT", "UNIT_AURA", "PARTY_KILL", "UNIT_DIED",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "UNIT_TARGET",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
}

local function Now()
    return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local CanAccess = CCL.CanAccess

local function Safe(v)
    if not CanAccess(v) then return "<secret>" end
    local kind = type(v)
    if kind == "nil" then return "nil" end
    if kind == "string" or kind == "number" or kind == "boolean" then
        local ok, text = pcall(tostring, v)
        return ok and text or ("<protected-" .. kind .. ">")
    end
    return "<" .. kind .. ">"
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return "<unavailable>" end
    local ok, value = pcall(fn, ...)
    return ok and Safe(value) or "<error>"
end

local function Context()
    return {
        targetGUID = SafeCall(UnitGUID, "target"),
        targetName = SafeCall(UnitName, "target"),
        focusGUID = SafeCall(UnitGUID, "focus"),
        petGUID = SafeCall(UnitGUID, "pet"),
    }
end

local function Add(kind, event, args, extra)
    nextID = nextID + 1
    local record = {
        id = nextID,
        phase = phase,
        t = Now() - startedAt,
        kind = kind,
        event = event,
        args = args or {},
        combat = InCombatLockdown and InCombatLockdown() and true or false,
        context = Context(),
        extra = extra,
    }
    records[#records + 1] = record
    if #records > MAX_RECORDS then table.remove(records, 1) end
    return record
end

local function PulseState()
    local filters = Blizzard_CombatLog_Filters
    local index, name
    if CanAccess(filters) and type(filters) == "table" then
        index = filters.currentFilter
        if CanAccess(index) and type(index) == "number"
            and CanAccess(filters.filters) and type(filters.filters) == "table" then
            local profile = filters.filters[index]
            if CanAccess(profile) and type(profile) == "table" then name = profile.name end
        end
    end
    return {
        filter = Safe(index),
        filterName = Safe(name),
        filteredEvents = SafeCall(C_CombatLog and C_CombatLog.AreFilteredEventsEnabled),
        chatFrameShown = SafeCall(ChatFrame2 and ChatFrame2.IsVisible, ChatFrame2),
        experiment = formatterProfile or "none",
        nearRefilter = Now() <= refilterUntil,
    }
end

local function Capture(event, ...)
    counts[event] = (counts[event] or 0) + 1
    local args, n = {}, select("#", ...)
    for i = 1, n do
        if event == "COMBAT_LOG_MESSAGE" and i == 1 then
            args[i] = "<protected-combat-message>"
        else
            args[i] = Safe(select(i, ...))
        end
    end
    local record = Add("event", event, args)
    if event == "COMBAT_LOG_MESSAGE" then
        record.pulse = PulseState()
    elseif event == "UNIT_COMBAT" or event == "UNIT_AURA" then
        local unit = args[1]
        if units[unit] or (unit and unit:match("^nameplate%d+$")) then
            record.unitGUID = SafeCall(UnitGUID, unit)
            record.engaged = SafeCall(UnitAffectingCombat, unit)
        end
    elseif event == "PARTY_KILL" or event == "UNIT_DIED" then
        local matched = {}
        for unit in pairs(units) do
            local guid = SafeCall(UnitGUID, unit)
            if not guid:match("^<") and guid ~= "nil" then
                if guid == args[1] then matched[#matched + 1] = "arg1=" .. unit end
                if guid == args[2] then matched[#matched + 1] = "arg2=" .. unit end
            end
        end
        table.sort(matched)
        record.extra = matched
    end
end

local function Readable(value, kind)
    if CanAccess(value) and type(value) == kind then return value end
end

local function TrackUnit(unit, reason)
    auraSnapshots[unit] = nil
    units[unit] = true
    Add("unit", reason, {unit, SafeCall(UnitGUID, unit), SafeCall(UnitAffectingCombat, unit)})
end

local function AuraIDs(unit, update)
    local query = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if not query then return end
    local guid = SafeCall(UnitGUID, unit)
    local prior = auraSnapshots[unit]
    local snapshot = {guid = guid}
    local args = {unit, "guid=" .. guid}
    update = Readable(update, "table")
    if update then args[#args + 1] = "full=" .. Safe(update.isFullUpdate) end
    for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
        local ok, ids = pcall(query, unit, filter)
        ids = ok and Readable(ids, "table")
        local set
        if ids then
            set = {}
            for i = 1, #ids do
                local id = Readable(ids[i], "number")
                if not id then
                    set = nil
                    break
                end
                set[id] = true
            end
        end
        local previous = prior and prior.guid == guid and guid ~= "nil" and prior[filter]
        local changes = {}
        if set then
            for id in pairs(set) do
                if not previous or not previous[id] then
                    changes[#changes + 1] = (previous and "+" or "=") .. id
                end
            end
            if previous then
                for id in pairs(previous) do
                    if not set[id] then changes[#changes + 1] = "-" .. id end
                end
            end
            table.sort(changes)
            snapshot[filter] = set
        end
        args[#args + 1] = filter .. "=" .. (set and table.concat(changes, ",")
            or (ok and "<unreadable>" or "<error>"))
    end
    local updated = update and Readable(update.updatedAuraInstanceIDs, "table")
    if updated then
        local ids = {}
        for i = 1, #updated do ids[i] = Safe(updated[i]) end
        args[#args + 1] = "updated=" .. table.concat(ids, ",")
    end
    auraSnapshots[unit] = snapshot
    local record = Add("aura", "INSTANCE_IDS", args)
    record.unitGUID = guid
end

local function SeedUnits()
    for _, unit in ipairs({"player", "pet", "target", "focus", "pettarget"}) do
        TrackUnit(unit, "BASELINE")
        if unit == "player" or SafeCall(UnitExists, unit) == "true" then AuraIDs(unit) end
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if SafeCall(UnitExists, unit) == "true" then
            TrackUnit(unit, "BASELINE")
            AuraIDs(unit)
        end
    end
end

local CORRELATION_WINDOW = 0.75

local function Candidates()
    local result, pulseUses = {}, {}
    local first = 1
    for i, hit in ipairs(records) do
        local aura = hit.kind == "aura"
        if hit.event == "UNIT_COMBAT" or aura then
            while records[first].t < hit.t - CORRELATION_WINDOW do first = first + 1 end
            local entry = {id = hit.id, t = hit.t, args = hit.args, guid = hit.unitGUID,
                candidates = {}, pulses = 0, otherResults = 0, aliases = 0, omitted = 0}
            for j = first, #records do
                local other = records[j]
                local dt = other.t - hit.t
                if dt > CORRELATION_WINDOW then break end
                local event, unit = other.event, other.args[1]
                local pulse = not aura and other.pulse and not other.pulse.nearRefilter
                local unitCast = event:match("^UNIT_SPELLCAST_") and
                    (unit == "player" or unit == "pet" or unit == "<secret>")
                local resultEvent = not aura and event == "UNIT_COMBAT" and i ~= j
                local combatText = not aura and event == "C_CombatText.GetCurrentEventInfo"
                    and (hit.args[1] == "player" or hit.args[1] == "pet")
                if other.phase == hit.phase and (pulse or unitCast or resultEvent or combatText
                    or (not aura and event == "PLAYER_SWING")) then
                    local alias = resultEvent and hit.unitGUID and hit.unitGUID ~= "nil"
                        and not hit.unitGUID:match("^<") and hit.unitGUID == other.unitGUID
                        and hit.args[1] ~= unit and hit.args[2] == other.args[2]
                        and hit.args[3] == other.args[3] and hit.args[4] == other.args[4]
                        and tonumber(hit.args[4]) ~= nil and hit.args[5] == other.args[5]
                    if #entry.candidates < 40 then
                        entry.candidates[#entry.candidates + 1] = {
                            id = other.id, dt = dt, event = event, alias = alias or nil,
                        }
                    else
                        entry.omitted = entry.omitted + 1
                    end
                    if pulse then
                        entry.pulses = entry.pulses + 1
                        pulseUses[other.id] = (pulseUses[other.id] or 0) + 1
                    elseif resultEvent then
                        entry.otherResults = entry.otherResults + 1
                        if alias then entry.aliases = entry.aliases + 1 end
                    end
                end
            end
            result[#result + 1] = entry
        end
    end
    for _, entry in ipairs(result) do
        for _, candidate in ipairs(entry.candidates) do
            candidate.pulseUses = pulseUses[candidate.id]
            if (candidate.pulseUses or 0) > 1 then entry.sharedPulse = true end
        end
    end
    return result
end

local function Metadata()
    local version, build, buildDate, interfaceVersion = GetBuildInfo()
    return {
        addonVersion = CCL.version,
        clientVersion = version,
        build = build,
        buildDate = buildDate,
        interfaceVersion = interfaceVersion,
        projectID = WOW_PROJECT_ID,
        forever = CCL:IsForeverClient(),
    }
end

local function Persist()
    if CleanCombatLogDB then
        CleanCombatLogDB.probe = {
            metadata = Metadata(), counts = counts,
            registration = registration, records = records,
            correlationWindow = CORRELATION_WINDOW, correlation = Candidates(),
        }
    end
end

local function RegisterAll()
    local registered = 0
    for _, event in ipairs(EVENTS) do
        local ok, result = pcall(function()
            frame:RegisterEvent(event)
            return frame:IsEventRegistered(event)
        end)
        if ok and result then
            registration[event] = "registered"
            registered = registered + 1
        else
            registration[event] = ok and "not-registered" or ("error: " .. Safe(result))
        end
    end
    return registered
end

local function UnregisterAll()
    for _, event in ipairs(EVENTS) do
        if frame:IsEventRegistered(event) then frame:UnregisterEvent(event) end
    end
end

local METER_TYPES = {
    [0]="DamageDone", [1]="Dps", [2]="HealingDone", [3]="Hps",
    [4]="Absorbs", [5]="Interrupts", [6]="Dispels", [7]="DamageTaken",
    [8]="AvoidableDamageTaken", [9]="Deaths", [10]="EnemyDamageTaken",
}

local function TableLength(v)
    if not CanAccess(v) or type(v) ~= "table" then return Safe(v) end
    local ok, n = pcall(function() return #v end)
    return ok and Safe(n) or "<error>"
end

local function Meter(quiet, encounter)
    local postCombat = not (InCombatLockdown and InCombatLockdown())
    local localTotals = {}
    if not C_DamageMeter then
        Add("api", "C_DamageMeter", {"unavailable"})
        if not quiet then CCL.Print("probe: C_DamageMeter unavailable.") end
        return
    end

    if C_DamageMeter.IsDamageMeterAvailable then
        local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
        Add("api", "C_DamageMeter.IsDamageMeterAvailable",
            {ok and Safe(available) or "<error>", ok and Safe(reason) or Safe(available)})
    end

    if not C_DamageMeter.GetCombatSessionFromType then return end
    local current = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1

    for metric = 0, 10 do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, current, metric)
        local args = {METER_TYPES[metric] or tostring(metric)}
        if not ok then
            args[#args+1] = "<error>"
            args[#args+1] = Safe(session)
        elseif not CanAccess(session) then
            args[#args+1] = "<secret-session>"
        elseif type(session) ~= "table" then
            args[#args+1] = Safe(session)
        else
            args[#args+1] = "total=" .. Safe(session.totalAmount)
            args[#args+1] = "max=" .. Safe(session.maxAmount)
            args[#args+1] = "duration=" .. Safe(session.durationSeconds)
            args[#args+1] = "sources=" .. TableLength(session.combatSources)
            local sources = postCombat and Readable(session.combatSources, "table")
            if sources and metric ~= 10 then
                for i = 1, #sources do
                    local source = Readable(sources[i], "table")
                    if source and Readable(source.isLocalPlayer, "boolean") then
                        localTotals[metric] = Safe(source.totalAmount)
                        args[#args + 1] = "localPlayer=" .. localTotals[metric]
                        break
                    end
                end
            end
        end
        Add("api", "C_DamageMeter.GetCombatSessionFromType", args)
    end
    if encounter then
        local incoming, woundRows, unknown, targetRows, targetAmount = 0, 0, 0, 0, 0
        for _, record in ipairs(records) do
            if record.id > encounter.first and record.id <= encounter.last
                and record.event == "UNIT_COMBAT" and record.args[2] == "WOUND" then
                local amount = tonumber(record.args[4])
                if record.args[1] == "player" then
                    woundRows = woundRows + 1
                    incoming = incoming + (amount or 0)
                    if not amount then unknown = unknown + 1 end
                elseif record.unitGUID and record.args[1] ~= "pet" then
                    targetRows = targetRows + 1
                    targetAmount = targetAmount + (amount or 0)
                end
            end
        end
        Add("compare", "DAMAGE_METER", {
            "start=#" .. encounter.first, "end=#" .. encounter.last,
            "capture=" .. ((records[1] and records[1].id <= encounter.first) and "retained" or "truncated"),
            "playerWounds=" .. woundRows, "playerReadableDamage=" .. incoming,
            "playerUnreadableAmounts=" .. unknown, "meterLocalDamageTaken=" .. (localTotals[7] or "?"),
            "meterLocalDamageDone=" .. (localTotals[0] or "?"),
            "unattributedTrackedWounds=" .. targetRows, "unattributedReadableDamage=" .. targetAmount,
        })
    end
    if not quiet then CCL.Print("probe: damage-meter snapshot captured.") end
end

local function CombatText(eventType)
    if not C_CombatText or not C_CombatText.GetCurrentEventInfo then return end
    local ok, a, b, c, d = pcall(C_CombatText.GetCurrentEventInfo)
    Add("api", "C_CombatText.GetCurrentEventInfo", ok
        and {eventType or "?", Safe(a), Safe(b), Safe(c), Safe(d)}
        or {eventType or "?", "<error>", Safe(a)})
end

local RECAP_FIELDS = {
    "timestamp", "event", "sourceGUID", "sourceName", "sourceFlags",
    "destGUID", "destName", "destFlags", "spellId", "spellID", "spellName",
    "spellSchool", "amount", "overkill", "school", "resisted", "blocked",
    "absorbed", "critical", "glancing", "crushing", "isOffHand", "currentHP",
}

local function DeathRecap(quiet, deathID)
    if deathID then
        local args = {"death=#" .. deathID}
        for i = #records, 1, -1 do
            local record = records[i]
            if record.id < deathID and record.event == "UNIT_COMBAT" and record.args[1] == "player" then
                args[#args + 1] = "#" .. record.id .. " " .. table.concat(record.args, "/")
                if #args >= 11 then break end
            end
        end
        Add("compare", "DEATH_RECAP", args)
    end
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then
        Add("api", "C_DeathRecap.GetRecapEvents", {"unavailable"})
        return
    end

    if C_DeathRecap.HasRecapEvents then
        local ok, hasEvents = pcall(C_DeathRecap.HasRecapEvents)
        Add("api", "C_DeathRecap.HasRecapEvents", {ok and Safe(hasEvents) or "<error>"})
        if ok and CanAccess(hasEvents) and hasEvents == false then return end
    end

    local ok, recap = pcall(C_DeathRecap.GetRecapEvents)
    if not ok then Add("api", "C_DeathRecap.GetRecapEvents", {"<error>", Safe(recap)}); return end
    if not CanAccess(recap) or type(recap) ~= "table" then
        Add("api", "C_DeathRecap.GetRecapEvents", {"<secret-or-unavailable>"}); return
    end

    local count = TableLength(recap)
    Add("api", "C_DeathRecap.GetRecapEvents", {"events=" .. count})
    for i = 1, math.min(tonumber(count) or 0, 10) do
        local info, args = recap[i], {"index=" .. i}
        if CanAccess(info) and type(info) == "table" then
            for _, field in ipairs(RECAP_FIELDS) do
                local fieldOK, value = pcall(function() return info[field] end)
                if fieldOK then args[#args+1] = field .. "=" .. Safe(value) end
            end
        else
            args[#args+1] = "<secret-event>"
        end
        Add("death-recap", "event", args)
    end
    if not quiet then CCL.Print("probe: death recap captured; events:", count) end
end

local function SetCombatTextUnit(unit)
    unit = (unit or "player"):lower()
    if not ({player=true,target=true,pet=true,focus=true})[unit] then
        CCL.Print("probe combattext unit must be player, target, pet, or focus.")
        return
    end
    if not C_CombatText or not C_CombatText.SetActiveUnit then
        CCL.Print("probe: C_CombatText.SetActiveUnit unavailable.")
        return
    end
    local ok, err = pcall(C_CombatText.SetActiveUnit, unit)
    Add("api", "C_CombatText.SetActiveUnit", {unit, ok and "ok" or "<error>", ok and "nil" or Safe(err)})
    if ok then
        combatTextUnit = unit
        CCL.Print("probe combat-text active unit set to", unit .. ".")
    else
        CCL.Print("probe combat-text unit change failed:", Safe(err))
    end
end

local function RestoreCombatText()
    if combatTextUnit and C_CombatText and C_CombatText.SetActiveUnit then
        pcall(C_CombatText.SetActiveUnit, "player")
    end
    combatTextUnit = nil
end

local function DeepCopy(value, seen)
    if not CanAccess(value) then error("protected formatter setting") end
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return copy
end

local function EnsureBlizzardCombatLogLoaded()
    if Blizzard_CombatLog_Filters then return true end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_CombatLog")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_CombatLog")
    end
    return Blizzard_CombatLog_Filters ~= nil
end

local function GetFormatterProfile(profileName)
    if not EnsureBlizzardCombatLogLoaded() then
        return nil, "Blizzard_CombatLog_Filters unavailable"
    end

    local container = Blizzard_CombatLog_Filters
    if not CanAccess(container) or type(container) ~= "table"
        or not CanAccess(container.filters) or type(container.filters) ~= "table" then
        return nil, "built-in combat-log filter table unavailable"
    end

    local index
    profileName = (profileName or "current"):lower()
    if profileName == "current" then
        local current = container.currentFilter
        if not CanAccess(current) or type(current) ~= "number" then
            return nil, "current filter index unavailable"
        end
        index = current
    elseif profileName == "myactions" or profileName == "mine" then
        index = 1
    elseif profileName == "me" or profileName == "incoming" then
        index = 2
    else
        return nil, "profile must be current, myactions, or me"
    end

    local profile = container.filters[index]
    if not CanAccess(profile) or type(profile) ~= "table"
        or not CanAccess(profile.filters) or type(profile.filters) ~= "table"
        or not CanAccess(profile.settings) or type(profile.settings) ~= "table" then
        return nil, "selected built-in filter profile is incomplete"
    end

    local ok, copy = pcall(DeepCopy, profile)
    if not ok then return nil, "formatter settings could not be copied safely" end
    return copy, nil, index
end

local function CreateFormatterPreview()
    if formatterPreview then return formatterPreview end

    local preview = CreateFrame("Frame", nil, UIParent)
    preview:SetSize(900, 150)
    preview:SetPoint("TOP", UIParent, "TOP", 0, -140)
    preview:SetFrameStrata("DIALOG")

    local bg = preview:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.72)

    local title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("CleanCombatLog secure formatter preview — protected messages are displayed unchanged")

    formatterPreviewRows = {}
    for i = 1, 8 do
        local row = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", 8, -8 - (i * 16))
        row:SetPoint("RIGHT", preview, "RIGHT", -8, 0)
        row:SetJustifyH("LEFT")
        row:SetText("")
        formatterPreviewRows[i] = row
    end

    formatterPreviewIndex = 0
    formatterPreview = preview
    return preview
end

local function ClearFormatterPreview()
    if not formatterPreviewRows then return end
    for _, row in ipairs(formatterPreviewRows) do row:SetText("") end
    formatterPreviewIndex = 0
end

local function ShowFormatterMessage(message, r, g, b)
    if not formatterPreview or not formatterPreview:IsShown() then return end
    if not formatterPreviewRows then return end

    formatterPreviewIndex = (formatterPreviewIndex % #formatterPreviewRows) + 1
    local row = formatterPreviewRows[formatterPreviewIndex]
    local ok, err = pcall(row.SetText, row, message)
    counts[ok and "PREVIEW_SET_TEXT_OK" or "PREVIEW_SET_TEXT_ERROR"] =
        (counts[ok and "PREVIEW_SET_TEXT_OK" or "PREVIEW_SET_TEXT_ERROR"] or 0) + 1
    if not ok and counts.PREVIEW_SET_TEXT_ERROR == 1 then
        Add("probe", "PREVIEW_SET_TEXT_ERROR", {Safe(err)})
    end

    if CanAccess(r) and CanAccess(g) and CanAccess(b)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        row:SetTextColor(r, g, b)
    else
        row:SetTextColor(1, 1, 1)
    end
end

local function SaveFormatterRestoreState()
    if formatterRestoreSettings then return true end
    local profile, err = GetFormatterProfile("current")
    if not profile then return false, err end

    formatterRestoreSettings = profile
    if C_CombatLog and C_CombatLog.AreFilteredEventsEnabled then
        local ok, enabled = pcall(C_CombatLog.AreFilteredEventsEnabled)
        if ok and CanAccess(enabled) and type(enabled) == "boolean" then
            formatterRestoreFilteredEvents = enabled
        end
    end
    return true
end

local function FormatterStatus()
    local hasApply = C_CombatLog and type(C_CombatLog.ApplyFilterSettings) == "function"
    local state = PulseState()

    CCL.Print("formatter ApplyFilterSettings:", tostring(hasApply))
    CCL.Print("formatter reported filter:", state.filterName, "currentFilter:", state.filter)
    CCL.Print("Blizzard combat chat frame visible:", state.chatFrameShown)
    CCL.Print("formatter active probe profile:", formatterProfile or "none")
    CCL.Print("formatter restore snapshot:", formatterRestoreSettings and "saved" or "not saved")
    if C_CombatLog and C_CombatLog.AreFilteredEventsEnabled then
        CCL.Print("formatter filtered events enabled:", SafeCall(C_CombatLog.AreFilteredEventsEnabled))
    end
end

local RestoreFormatter

local function ApplyFormatter(profileName, mode)
    local modeName = (mode or "compact"):lower()
    if modeName ~= "compact" and modeName ~= "full" then
        CCL.Print("probe: formatter mode must be compact or full.")
        return
    end
    mode = modeName
    if not C_CombatLog or type(C_CombatLog.ApplyFilterSettings) ~= "function" then
        CCL.Print("probe: C_CombatLog.ApplyFilterSettings unavailable.")
        Add("api", "C_CombatLog.ApplyFilterSettings", {"unavailable"})
        return
    end

    local profile, err, index = GetFormatterProfile(profileName)
    if not profile then
        CCL.Print("probe: formatter profile unavailable:", err)
        return
    end

    local hadSnapshot = formatterRestoreSettings ~= nil
    local saved, saveErr = SaveFormatterRestoreState()
    if not saved then
        CCL.Print("probe: cannot snapshot current combat-log settings:", saveErr)
        Add("api", "C_CombatLog.ApplyFilterSettings", {"snapshot-failed", saveErr})
        return
    end

    profile.settings.fullText = (mode == "full")
    profile.settings.timestamp = false
    profile.settings.amountColoring = true
    profile.settings.amountSchoolColoring = true

    phase = phase + 1
    refilterUntil = Now() + 0.75
    local ok, result = pcall(C_CombatLog.ApplyFilterSettings, profile)
    Add("api", "C_CombatLog.ApplyFilterSettings",
        {profileName or "current", mode, "index=" .. tostring(index or "?"), ok and "ok" or "<error>", ok and "nil" or Safe(result)})

    if not ok then
        CCL.Print("probe: ApplyFilterSettings failed:", Safe(result))
        if not hadSnapshot then
            formatterRestoreSettings, formatterRestoreFilteredEvents = nil, nil
        else
            RestoreFormatter()
        end
        return
    end

    formatterProfile = (profileName or "current") .. "/" .. mode
    local preview = CreateFormatterPreview()
    ClearFormatterPreview()
    preview:Show()

    if C_CombatLog.RefilterEntries then
        pcall(C_CombatLog.RefilterEntries)
    end

    CCL.Print("probe: secure combat-log formatter applied:", formatterProfile .. ".")
    CCL.Print("Protected COMBAT_LOG_MESSAGE lines will appear in the preview unchanged.")
end

RestoreFormatter = function()
    if not formatterRestoreSettings then
        CCL.Print("probe: no formatter restore snapshot is available.")
        return
    end
    if not C_CombatLog or type(C_CombatLog.ApplyFilterSettings) ~= "function" then
        CCL.Print("probe: C_CombatLog.ApplyFilterSettings unavailable; cannot restore.")
        return
    end

    phase = phase + 1
    refilterUntil = Now() + 0.75
    local ok, result = pcall(C_CombatLog.ApplyFilterSettings, formatterRestoreSettings)
    Add("api", "C_CombatLog.ApplyFilterSettings", {"restore", ok and "ok" or "<error>", ok and "nil" or Safe(result)})

    if ok and formatterRestoreFilteredEvents ~= nil and C_CombatLog.SetFilteredEventsEnabled then
        pcall(C_CombatLog.SetFilteredEventsEnabled, formatterRestoreFilteredEvents)
    end
    if ok and C_CombatLog.RefilterEntries then pcall(C_CombatLog.RefilterEntries) end

    if ok then
        formatterProfile = nil
        formatterRestoreSettings = nil
        formatterRestoreFilteredEvents = nil
        if formatterPreview then formatterPreview:Hide() end
        CCL.Print("probe: original built-in combat-log formatter settings restored.")
    else
        CCL.Print("probe: formatter restore failed:", Safe(result))
    end
end

local function FormatterCommand(text)
    local action, profile = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
    action = (action or "status"):lower()
    profile = profile ~= "" and profile:lower() or "current"

    if action == "" or action == "status" then
        FormatterStatus()
    elseif action == "compact" or action == "full" then
        ApplyFormatter(profile, action)
    elseif action == "refilter" then
        if C_CombatLog and C_CombatLog.RefilterEntries then
            phase = phase + 1
            refilterUntil = Now() + 0.75
            local ok, err = pcall(C_CombatLog.RefilterEntries)
            Add("api", "C_CombatLog.RefilterEntries", {ok and "ok" or "<error>", ok and "nil" or Safe(err)})
            CCL.Print(ok and "probe: combat-log refilter requested." or ("probe: refilter failed: " .. Safe(err)))
        else
            CCL.Print("probe: C_CombatLog.RefilterEntries unavailable.")
        end
    elseif action == "restore" then
        RestoreFormatter()
    elseif action == "preview" then
        local preview = CreateFormatterPreview()
        if profile == "off" then preview:Hide() else preview:Show() end
        CCL.Print("probe: formatter preview", preview:IsShown() and "shown." or "hidden.")
    else
        CCL.Print("formatter: status | compact [current|myactions|me] | full [current|myactions|me] | refilter | restore | preview [on|off]")
    end
end

local function PrintRecord(r)
    local args = r.args and table.concat(r.args, " | ") or ""
    local target = r.context and r.context.targetGUID
    local pulse = r.pulse or (r.event == "MARK" and r.extra)
    CCL.Print(string.format("#%d %8.3f", r.id, r.t), r.kind, r.event, args,
        r.unitGUID and ("unitGUID=" .. r.unitGUID) or "",
        target and target ~= "nil" and ("target=" .. target) or "",
        pulse and ("filter=" .. pulse.filter .. "/" .. pulse.filterName .. " enabled=" .. pulse.filteredEvents
            .. " visible=" .. pulse.chatFrameShown .. " experiment=" .. pulse.experiment
            .. (pulse.nearRefilter and " near-refilter" or "")) or "",
        (r.event == "PARTY_KILL" or r.event == "UNIT_DIED") and table.concat(r.extra or {}, " ") or "")
end

function CCL:StartCombatProbe()
    if active then self.Print("probe is already running."); return end
    records, counts, registration = {}, {}, {}
    units, auraSnapshots = {}, {}
    nextID, phase, refilterUntil, comparisonStart = 0, 0, 0, nil
    startedAt, active = Now(), true
    local registered = RegisterAll()
    Add("probe", "START", {}, Metadata())
    SeedUnits()
    self.Print("Forever combat probe started;", registered, "of", #EVENTS, "candidate events registered.")
end

function CCL:StopCombatProbe()
    if not active then self.Print("probe is not running."); return end
    Add("probe", "STOP")
    active = false
    UnregisterAll()
    RestoreCombatText()
    if formatterRestoreSettings then RestoreFormatter() end
    if formatterPreview then formatterPreview:Hide() end
    Persist()
    self.Print("probe stopped;", #records, "sanitised records saved in CleanCombatLogDB.probe.")
end

function CCL:PrintCombatProbeStatus()
    local version, build, _, interfaceVersion = GetBuildInfo()
    self.Print("probe:", active and "RUNNING" or "stopped", "records:", #records)
    self.Print("client:", version or "?", "build:", build or "?", "interface:", interfaceVersion or "?", "project:", tostring(WOW_PROJECT_ID))
    self.Print("Forever project:", tostring(self:IsForeverClient()))
    self.Print("PLAYER_SWING:", registration.PLAYER_SWING or "not attempted", "UNIT_COMBAT:", registration.UNIT_COMBAT or "not attempted")
    self.Print("COMBAT_LOG_MESSAGE:", registration.COMBAT_LOG_MESSAGE or "not attempted")
    self.Print("C_DamageMeter:", tostring(C_DamageMeter ~= nil), "C_DeathRecap:", tostring(C_DeathRecap ~= nil))
    self.Print("C_CombatText.GetCurrentEventInfo:", tostring(C_CombatText and C_CombatText.GetCurrentEventInfo ~= nil))
    if C_CombatText and C_CombatText.GetActiveUnit then self.Print("C_CombatText active unit:", SafeCall(C_CombatText.GetActiveUnit), "probe mode:", combatTextUnit or "unchanged") end
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then self.Print("C_CombatLog.IsCombatLogRestricted:", SafeCall(C_CombatLog.IsCombatLogRestricted)) end
end

function CCL:PrintCombatProbeSummary()
    local names = {}; for event in pairs(counts) do names[#names+1] = event end; table.sort(names)
    self.Print("probe summary:", #records, "records across", #names, "event types.")
    for _, event in ipairs(names) do self.Print(event .. ":", counts[event]) end
end

function CCL:DumpCombatProbe(limit)
    limit = math.max(1, math.min(tonumber(limit) or 40, 200))
    for i = math.max(1, #records-limit+1), #records do PrintRecord(records[i]) end
end

function CCL:PrintCombatProbeRegistrations()
    for _, event in ipairs(EVENTS) do self.Print(event .. ":", registration[event] or "not attempted") end
end

function CCL:HandleProbeCommand(rest)
    local cmd, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$"); cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "status" then self:PrintCombatProbeStatus()
    elseif cmd == "start" then self:StartCombatProbe()
    elseif cmd == "stop" then self:StopCombatProbe()
    elseif cmd == "summary" then self:PrintCombatProbeSummary()
    elseif cmd == "dump" then self:DumpCombatProbe(arg)
    elseif cmd == "events" then self:PrintCombatProbeRegistrations()
    elseif cmd == "meter" then Meter(false)
    elseif cmd == "death" then DeathRecap(false)
    elseif cmd == "combattext" then SetCombatTextUnit(arg ~= "" and arg or "player")
    elseif cmd == "formatter" then FormatterCommand(arg)
    elseif cmd == "mark" then
        if not active then self.Print("start the probe before adding a marker."); return end
        phase = phase + 1
        local marker = Add("probe", "MARK", {arg}, PulseState())
        self.Print("probe marker #" .. marker.id, arg)
    elseif cmd == "correlate" then
        local report = Candidates()
        local limit = math.max(1, math.min(tonumber(arg) or 10, 40))
        for i = math.max(1, #report - limit + 1), #report do
            local result = report[i]
            self.Print("result #" .. result.id, table.concat(result.args, " | "),
                "pulses=" .. result.pulses, result.sharedPulse and "shared pulse" or "",
                "nearby results=" .. result.otherResults, "possible aliases=" .. result.aliases,
                "omitted=" .. result.omitted)
            for _, candidate in ipairs(result.candidates) do
                self.Print(string.format("  #%d %+.3fs", candidate.id, candidate.dt), candidate.event,
                    candidate.pulseUses and ("pulse uses=" .. candidate.pulseUses) or "",
                    candidate.alias and "possible alias" or "")
            end
        end
    elseif cmd == "clear" then
        records, counts, auraSnapshots, comparisonStart = {}, {}, {}, nil
        if CleanCombatLogDB then CleanCombatLogDB.probe = nil end
        self.Print("probe data cleared.")
    else self.Print("probe commands: start, stop, status, summary, dump [n], events, meter, death, mark <label>, correlate [n], combattext <unit>, formatter <action>, clear") end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if not active then return end
    if event == "COMBAT_LOG_APPLY_FILTER_SETTINGS" or event == "COMBAT_LOG_REFILTER_ENTRIES" then
        phase = phase + 1
        refilterUntil = Now() + CORRELATION_WINDOW
    end
    Capture(event, ...)

    local firstArg = ...
    local unit = Readable(firstArg, "string")
    if event == "NAME_PLATE_UNIT_ADDED" and unit then
        TrackUnit(unit, event)
        AuraIDs(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" and unit then
        units[unit], auraSnapshots[unit] = nil, nil
    elseif event == "UNIT_AURA" and unit and (units[unit] or unit:match("^nameplate%d+$")) then
        AuraIDs(unit, select(2, ...))
    elseif event == "PLAYER_TARGET_CHANGED" then
        TrackUnit("target", event)
        AuraIDs("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        TrackUnit("focus", event)
        AuraIDs("focus")
    elseif event == "UNIT_PET" and unit == "player" then
        TrackUnit("pet", event)
        TrackUnit("pettarget", event)
        AuraIDs("pet")
        AuraIDs("pettarget")
    elseif event == "UNIT_TARGET" and unit == "pet" then
        TrackUnit("pettarget", event)
        AuraIDs("pettarget")
    end

    if event == "COMBAT_LOG_MESSAGE" then
        ShowFormatterMessage(...)
    elseif event == "COMBAT_TEXT_UPDATE" then
        CombatText(Safe(select(1, ...)))
    elseif (event == "PLAYER_TARGET_CHANGED" and combatTextUnit == "target")
        or (event == "PLAYER_FOCUS_CHANGED" and combatTextUnit == "focus") then
        SetCombatTextUnit(combatTextUnit)
    elseif event == "PLAYER_DEAD" and C_Timer and C_Timer.After then
        local capture, deathID = records, nextID
        C_Timer.After(0.5, function()
            if active and records == capture then
                DeathRecap(true, deathID)
                Persist()
            end
        end)
    end

    if event == "PLAYER_REGEN_DISABLED" then
        comparisonStart = nextID
    elseif event == "PLAYER_REGEN_ENABLED" then
        local capture = records
        local encounter = comparisonStart and {first = comparisonStart, last = nextID}
        comparisonStart = nil
        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, function()
                if active and records == capture and not comparisonStart then
                    Meter(true, encounter)
                    Persist()
                end
            end)
        else
            Meter(true, encounter)
            Persist()
        end
    end
end)
