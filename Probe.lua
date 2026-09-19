local addonName, CCL = ...

local frame = CreateFrame("Frame")
CCL.Probe = frame

local active, startedAt, combatTextUnit = false, 0, nil
local records, counts, registration = {}, {}, {}
local MAX_RECORDS = 2500

local EVENTS = {
    "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE",
    "COMBAT_LOG_MESSAGE", "COMBAT_TEXT_UPDATE",
    "UNIT_COMBAT", "UNIT_AURA",
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

local function CanAccess(v)
    if v == nil then return true end
    if canaccessvalue then
        local ok, result = pcall(canaccessvalue, v)
        if ok then return result and true or false end
    end
    if issecretvalue then
        local ok, result = pcall(issecretvalue, v)
        if ok then return not result end
    end
    return true
end

local function Safe(v)
    if not CanAccess(v) then return "<secret>" end
    local kind = type(v)
    if kind == "nil" then return "nil" end
    if kind == "string" or kind == "number" or kind == "boolean" then
        local ok, text = pcall(tostring, v)
        return ok and text or ("<protected-" .. kind .. ">")
    end
    if kind == "table" and issecrettable then
        local ok, secret = pcall(issecrettable, v)
        if ok and secret then return "<secret-table>" end
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
    records[#records + 1] = {
        t = Now() - startedAt,
        kind = kind,
        event = event,
        args = args or {},
        combat = InCombatLockdown and InCombatLockdown() and true or false,
        context = Context(),
        extra = extra,
    }
    if #records > MAX_RECORDS then table.remove(records, 1) end
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
    Add("event", event, args)
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
    }
end

local function Persist()
    if CleanCombatLogDB then
        CleanCombatLogDB.probe = {
            metadata = Metadata(), counts = counts,
            registration = registration, records = records,
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
    if not CanAccess(v) or type(v) ~= "table" then return "<secret>" end
    local ok, n = pcall(function() return #v end)
    return ok and tostring(n) or "<error>"
end

local function Meter(quiet)
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
            args[#args+1], args[#args+1] = "<error>", Safe(session)
        elseif not CanAccess(session) then
            args[#args+1] = "<secret-session>"
        elseif type(session) ~= "table" then
            args[#args+1] = Safe(session)
        else
            args[#args+1] = "total=" .. Safe(session.totalAmount)
            args[#args+1] = "max=" .. Safe(session.maxAmount)
            args[#args+1] = "duration=" .. Safe(session.durationSeconds)
            args[#args+1] = "sources=" .. TableLength(session.combatSources)
        end
        Add("api", "C_DamageMeter.GetCombatSessionFromType", args)
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

local function DeathRecap(quiet)
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then
        Add("api", "C_DeathRecap.GetRecapEvents", {"unavailable"})
        return
    end

    if C_DeathRecap.HasRecapEvents then
        local ok, hasEvents = pcall(C_DeathRecap.HasRecapEvents)
        Add("api", "C_DeathRecap.HasRecapEvents", {ok and Safe(hasEvents) or "<error>"})
        if ok and hasEvents == false then return end
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
                if fieldOK and value ~= nil then args[#args+1] = field .. "=" .. Safe(value) end
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

local function PrintRecord(r)
    local args = r.args and table.concat(r.args, " | ") or ""
    local target = r.context and r.context.targetGUID
    CCL.Print(string.format("%8.3f", r.t or 0), r.kind or "?", r.event or "?", args,
        target and target ~= "nil" and ("target=" .. target) or "")
end

function CCL:StartCombatProbe()
    if active then self.Print("probe is already running."); return end
    records, counts, registration = {}, {}, {}
    startedAt, active = Now(), true
    local registered = RegisterAll()
    Add("probe", "START", {}, Metadata())
    self.Print("Forever combat probe started;", registered, "of", #EVENTS, "candidate events registered.")
end

function CCL:StopCombatProbe()
    if not active then self.Print("probe is not running."); return end
    Add("probe", "STOP")
    Persist(); UnregisterAll(); RestoreCombatText(); active = false
    self.Print("probe stopped;", #records, "sanitised records saved in CleanCombatLogDB.probe.")
end

function CCL:PrintCombatProbeStatus()
    local version, build, _, interfaceVersion = GetBuildInfo()
    self.Print("probe:", active and "RUNNING" or "stopped", "records:", #records)
    self.Print("client:", version or "?", "build:", build or "?", "interface:", interfaceVersion or "?", "project:", tostring(WOW_PROJECT_ID))
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
    elseif cmd == "clear" then records, counts, registration = {}, {}, {}; if CleanCombatLogDB then CleanCombatLogDB.probe = nil end; self.Print("probe data cleared.")
    else self.Print("probe commands: start, stop, status, summary, dump [n], events, meter, death, combattext <unit>, clear") end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if not active then return end
    Capture(event, ...)

    if event == "COMBAT_TEXT_UPDATE" then
        CombatText(Safe(select(1, ...)))
    elseif (event == "PLAYER_TARGET_CHANGED" and combatTextUnit == "target")
        or (event == "PLAYER_FOCUS_CHANGED" and combatTextUnit == "focus") then
        SetCombatTextUnit(combatTextUnit)
    elseif event == "PLAYER_DEAD" and C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() if active then DeathRecap(true); Persist() end end)
    end

    if event == "PLAYER_REGEN_ENABLED" and C_Timer and C_Timer.After then
        C_Timer.After(0.25, function() if active then Meter(true); Persist() end end)
    elseif event == "DAMAGE_METER_RESET" then
        Persist()
    end
end)
