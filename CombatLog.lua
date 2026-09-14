local addonName, CCL = ...

local frame = CreateFrame("Frame")
CCL.CombatLog = frame

local playerGUID
local petGUID
local enabled = false

local schoolFallback = {
    [1]  = {0.78, 0.61, 0.43}, -- Physical
    [2]  = {1.00, 0.90, 0.50}, -- Holy
    [4]  = {1.00, 0.50, 0.00}, -- Fire
    [8]  = {0.30, 1.00, 0.30}, -- Nature
    [16] = {0.50, 1.00, 1.00}, -- Frost
    [32] = {0.50, 0.50, 1.00}, -- Shadow
    [64] = {1.00, 0.50, 1.00}, -- Arcane
}

local missTypes = {
    ABSORB = "Absorb",
    BLOCK = "Block",
    DEFLECT = "Deflect",
    DODGE = "Dodge",
    EVADE = "Evade",
    IMMUNE = "Immune",
    MISS = "Miss",
    PARRY = "Parry",
    REFLECT = "Reflect",
    RESIST = "Resist",
}

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5)
    )
end

local function SchoolColor(school)
    if COMBATLOG_DEFAULT_COLORS and COMBATLOG_DEFAULT_COLORS.schoolColoring then
        local color = COMBATLOG_DEFAULT_COLORS.schoolColoring[school]
        if color then
            return Hex(color.r, color.g, color.b)
        end
    end

    local color = schoolFallback[school] or schoolFallback[1]
    return Hex(color[1], color[2], color[3])
end

local function ShortName(name)
    if not name or name == "" then
        return "?"
    end

    if name:find("[%s%-]") then
        return (name:gsub("(%a)[%l]*[%s%-]*", "%1"))
    end

    return name:sub(1, 3)
end

local function Timestamp(timestamp)
    if date then
        return date("%H:%M:%S", timestamp)
    end
    return ""
end

local function IsMine(guid)
    return guid and (guid == playerGUID or guid == petGUID)
end

local function AddDamageModifiers(column, text, blocked, resisted, absorbed, overkill, critical, glancing, crushing, isPet)
    local mods = {}

    if blocked and blocked > 0 then mods[#mods + 1] = "b" end
    if crushing then mods[#mods + 1] = "c" end
    if glancing then mods[#mods + 1] = "g" end
    if resisted and resisted > 0 then mods[#mods + 1] = "r" end
    if absorbed and absorbed > 0 then mods[#mods + 1] = "a" end
    if overkill and overkill > 0 then mods[#mods + 1] = "k" end
    if critical then mods[#mods + 1] = "•" end
    if isPet then mods[#mods + 1] = "·" end

    if #mods == 0 then
        return text
    end

    local modText = table.concat(mods, " ")

    if column == 1 then
        return text .. CCL.COLORS.beige .. " " .. modText .. "|r"
    elseif column == 3 then
        return CCL.COLORS.beige .. modText .. " |r" .. text
    end

    return text
end

local function Route(sourceGUID, destGUID)
    if IsMine(sourceGUID) then
        return 3 -- outgoing
    elseif IsMine(destGUID) then
        return 1 -- incoming
    end
end

local function HandleEvent(...)
    local timestamp, subEvent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags = ...

    if not subEvent then
        return
    end

    if not (IsMine(sourceGUID) or IsMine(destGUID)) then
        return
    end

    local payload = {select(12, ...)}
    local column = Route(sourceGUID, destGUID)
    local sourceIsMine = IsMine(sourceGUID)
    local destIsMine = IsMine(destGUID)
    local isPet = (sourceGUID == petGUID or destGUID == petGUID)
    local timeText = Timestamp(timestamp)

    if subEvent == "SWING_DAMAGE" then
        local amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing =
            unpack(payload)

        local effective = math.max(0, (amount or 0) - math.max(0, overkill or 0))
        local text = SchoolColor(school or 1) .. effective .. "|r"
        text = AddDamageModifiers(column, text, blocked, resisted, absorbed, overkill, critical, glancing, crushing, isPet)

        local tooltip = ("%s %s melee swing hit %s for %s."):format(
            timeText,
            sourceIsMine and "Your" or (sourceName or "Unknown"),
            destIsMine and "you" or (destName or "Unknown"),
            tostring(amount or 0)
        )

        CCL:AddRow(column, text, tooltip)
        return
    end

    if subEvent == "RANGE_DAMAGE" or
       subEvent == "SPELL_DAMAGE" or
       subEvent == "SPELL_PERIODIC_DAMAGE" or
       subEvent == "DAMAGE_SHIELD" or
       subEvent == "DAMAGE_SPLIT" then

        local spellId, spellName, spellSchool, amount, overkill, school,
              resisted, blocked, absorbed, critical, glancing, crushing =
            unpack(payload)

        local effective = math.max(0, (amount or 0) - math.max(0, overkill or 0))
        local colorSchool = (subEvent == "RANGE_DAMAGE") and (school or spellSchool) or spellSchool
        local text = SchoolColor(colorSchool or 1) .. effective .. "|r"
        text = AddDamageModifiers(column, text, blocked, resisted, absorbed, overkill, critical, glancing, crushing, isPet)

        local tooltip = ("%s %s %s %s %s for %s."):format(
            timeText,
            sourceIsMine and "Your" or ((sourceName or "Unknown") .. "'s"),
            spellName or "spell",
            subEvent == "SPELL_PERIODIC_DAMAGE" and "damaged" or "hit",
            destIsMine and "you" or (destName or "Unknown"),
            tostring(amount or 0)
        )

        CCL:AddRow(column, text, tooltip)
        return
    end

    if subEvent == "ENVIRONMENTAL_DAMAGE" then
        local environmentalType, amount, overkill, school, resisted, blocked,
              absorbed, critical, glancing, crushing = unpack(payload)

        local text = SchoolColor(school or 1) .. tostring(amount or 0) .. "|r"
        text = AddDamageModifiers(1, text, blocked, resisted, absorbed, overkill, critical, glancing, crushing, false)

        CCL:AddRow(1, text,
            ("%s You suffered %s from %s."):format(timeText, tostring(amount or 0), tostring(environmentalType or "environment")))
        return
    end

    if subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, amount, overheal, absorbed, critical = unpack(payload)
        local effective = math.max(0, (amount or 0) - math.max(0, overheal or 0))

        if effective <= 0 then
            return
        end

        local arrow = sourceIsMine and not destIsMine and "» " or "« "
        local color = subEvent == "SPELL_PERIODIC_HEAL" and CCL.COLORS.lightgreen or CCL.COLORS.green
        local prefix = critical and "• " or ""
        local suffix = isPet and " ·" or ""
        local text = color .. prefix .. arrow .. effective .. suffix .. "|r"

        CCL:AddRow(2, text,
            ("%s %s %s healed %s for %s%s."):format(
                timeText,
                sourceIsMine and "Your" or ((sourceName or "Unknown") .. "'s"),
                spellName or "spell",
                destIsMine and "you" or (destName or "Unknown"),
                tostring(amount or 0),
                overheal and overheal > 0 and (" (" .. overheal .. " overheal)") or ""
            ))
        return
    end

    if subEvent == "SWING_MISSED" then
        local missType, amountMissed = unpack(payload)
        local text = CCL.COLORS.beige .. (missTypes[missType] or tostring(missType or "Miss")) .. (isPet and " ·" or "") .. "|r"

        CCL:AddRow(column, text,
            ("%s %s melee swing missed %s: %s."):format(
                timeText,
                sourceIsMine and "Your" or (sourceName or "Unknown"),
                destIsMine and "you" or (destName or "Unknown"),
                missTypes[missType] or tostring(missType or "Miss")
            ))
        return
    end

    if subEvent == "RANGE_MISSED" or subEvent == "SPELL_MISSED" or
       subEvent == "SPELL_PERIODIC_MISSED" or subEvent == "DAMAGE_SHIELD_MISSED" then

        local spellId, spellName, spellSchool, missType, amountMissed = unpack(payload)
        local text = SchoolColor(spellSchool or 1) .. (missTypes[missType] or tostring(missType or "Miss")) .. "|r"

        CCL:AddRow(column, text,
            ("%s %s %s missed %s: %s."):format(
                timeText,
                sourceIsMine and "Your" or ((sourceName or "Unknown") .. "'s"),
                spellName or "spell",
                destIsMine and "you" or (destName or "Unknown"),
                missTypes[missType] or tostring(missType or "Miss")
            ))
        return
    end

    if subEvent:find("AURA_APPLIED") or subEvent:find("AURA_REMOVED") or subEvent:find("AURA_REFRESH") then
        local spellId, spellName, spellSchool, auraType, amount = unpack(payload)

        if auraType == "DEBUFF" and destIsMine then
            column = 1
        elseif auraType == "DEBUFF" and sourceIsMine then
            column = 3
        elseif auraType == "BUFF" and sourceIsMine and destIsMine then
            column = 2
        else
            return
        end

        local applied = subEvent:find("AURA_APPLIED") ~= nil
        local removed = subEvent:find("AURA_REMOVED") ~= nil
        local marker = applied and "++" or removed and "--" or "↻"
        local short = column == 2 and (spellName or "?") or ShortName(spellName)
        local stack = amount and (" (" .. amount .. ")") or ""

        local text
        if column == 1 then
            text = SchoolColor(spellSchool or 1) .. short .. stack .. "|r" .. CCL.COLORS.beige .. " " .. marker .. "|r"
        elseif column == 3 then
            text = CCL.COLORS.beige .. marker .. " |r" .. SchoolColor(spellSchool or 1) .. short .. stack .. "|r"
        else
            text = SchoolColor(spellSchool or 1) .. marker .. " " .. short .. stack .. " " .. marker .. "|r"
        end

        CCL:AddRow(column, text,
            ("%s %s %s: %s."):format(timeText, tostring(auraType or "Aura"), marker, spellName or "Unknown"))
        return
    end

    if subEvent == "PARTY_KILL" or subEvent == "UNIT_DIED" or
       subEvent == "UNIT_DESTROYED" or subEvent == "UNIT_DISSIPATES" then

        local name = destName or "Unknown"
        CCL:AddRow(2, CCL.COLORS.beige .. "†† " .. name .. " ††|r",
            ("%s %s."):format(timeText, subEvent:gsub("_", " ")))
    end
end

local function RefreshGUIDs()
    playerGUID = UnitGUID("player")
    petGUID = UnitGUID("pet")
end

function CCL:EnableCLEU()
    if enabled then
        self.Print("CLEU is already enabled.")
        return true
    end

    local api = self:GetCombatLogAPIMode()
    if not api then
        self.Print("No supported combat-log payload API was found.")
        return false
    end

    local ok, result = pcall(function()
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        return frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    enabled = ok and result and true or false

    if enabled then
        self.Print("CLEU registration succeeded using", api .. ".")
        self.Print("Attack a target; supported events should now populate the shell.")
    else
        self.Print("CLEU registration did not succeed.", ok and "" or tostring(result))
        self.Print("If the client reports ADDON_ACTION_FORBIDDEN, Forever is using the restricted model.")
    end

    return enabled
end

function CCL:DisableCLEU()
    if frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
        frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end

    enabled = false
    self.Print("CLEU disabled.")
end

function CCL:ToggleCLEU()
    if enabled or frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
        self:DisableCLEU()
    else
        self:EnableCLEU()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        RefreshGUIDs()
        return
    elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local blockedAddon, action = ...
        if blockedAddon == addonName or blockedAddon == "CleanCombatLog" then
            CCL.Print(event .. ":", tostring(action or "unknown action"))
            if action and tostring(action):find("COMBAT_LOG") then
                CCL.Print("This is direct evidence that the client restricts combat-log registration.")
            end
        end
        return
    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            RefreshGUIDs()
        end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        CCL:AddRow(2, CCL.COLORS.red .. "++ Combat ++|r", "Entered combat.")
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        CCL:AddRow(2, CCL.COLORS.green .. "-- Combat --|r", "Left combat.")
        return
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local getter = CCL.GetCurrentCombatLogEventInfo
        if not getter then
            return
        end

        local values = {CCL:GetCurrentCombatLogEventInfo()}
        if #values > 0 then
            HandleEvent(unpack(values))
        end
    end
end)
