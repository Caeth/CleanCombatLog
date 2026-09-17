local addonName, CCL = ...

-- Experimental player-centric combat adapter for Midnight/Forever restrictions.
-- This module is opt-in and deliberately does not replace the CLEU test path.
-- Enable with /ccl unitcombat.

local frame = CreateFrame("Frame")
CCL.PlayerCombat = frame

local enabled = false
local playerAutoAttacking = false
local lastPlayerSpellAt = 0
local lastPetSpellAt = 0
local lastPlayerSpellID
local lastPetSpellID

local OUTGOING_WINDOW = 1.5

local MISS_ACTIONS = {
    ABSORB = true,
    BLOCK = true,
    DEFLECT = true,
    DODGE = true,
    EVADE = true,
    IMMUNE = true,
    MISS = true,
    PARRY = true,
    REFLECT = true,
    RESIST = true,
}

local SCHOOL_COLORS = {
    [1]  = {0.78, 0.61, 0.43}, -- Physical
    [2]  = {1.00, 0.90, 0.50}, -- Holy
    [4]  = {1.00, 0.50, 0.00}, -- Fire
    [8]  = {0.30, 1.00, 0.30}, -- Nature
    [16] = {0.50, 1.00, 1.00}, -- Frost
    [32] = {0.50, 0.50, 1.00}, -- Shadow
    [64] = {1.00, 0.50, 1.00}, -- Arcane
}

local function CanAccess(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end

    return true
end

local function GetSchoolColor(schoolMask)
    if not CanAccess(schoolMask) then
        return 1, 1, 1
    end

    local color = SCHOOL_COLORS[schoolMask] or SCHOOL_COLORS[1]
    return color[1], color[2], color[3]
end

local function RecentOutgoingSource()
    local now = GetTime()
    local playerRecent = (now - lastPlayerSpellAt) <= OUTGOING_WINDOW
    local petRecent = (now - lastPetSpellAt) <= OUTGOING_WINDOW

    if playerRecent and petRecent then
        if lastPlayerSpellAt >= lastPetSpellAt then
            return "player", lastPlayerSpellID
        end
        return "pet", lastPetSpellID
    elseif playerRecent then
        return "player", lastPlayerSpellID
    elseif petRecent then
        return "pet", lastPetSpellID
    elseif playerAutoAttacking then
        return "player", nil
    end

    return nil, nil
end

local function CritPrefix(flagText)
    if flagText == "CRITICAL" then
        return "•"
    end

    return ""
end

local function HandleIncoming(action, flagText, amount, schoolMask)
    if action == "WOUND" then
        local r, g, b = GetSchoolColor(schoolMask)
        CCL:AddSecretValueRow(1, amount, r, g, b, "", CritPrefix(flagText))
        return
    end

    if action == "HEAL" then
        CCL:AddSecretValueRow(2, amount, 0.35, 0.85, 0.35, "«", CritPrefix(flagText))
        return
    end

    if MISS_ACTIONS[action] then
        CCL:AddSecretValueRow(1, action, 0.75, 0.75, 0.75, "", "")
    end
end

local function HandleOutgoing(action, flagText, amount, schoolMask)
    local source, spellID = RecentOutgoingSource()
    if not source then
        return
    end

    if action == "WOUND" then
        local r, g, b = GetSchoolColor(schoolMask)
        local prefix = source == "pet" and "·" or ""
        CCL:AddSecretValueRow(3, amount, r, g, b, prefix, CritPrefix(flagText))
        return
    end

    if action == "HEAL" then
        local prefix = source == "pet" and "·»" or "»"
        CCL:AddSecretValueRow(2, amount, 0.35, 0.85, 0.35, prefix, CritPrefix(flagText))
        return
    end

    if MISS_ACTIONS[action] then
        local prefix = source == "pet" and "·" or ""
        CCL:AddSecretValueRow(3, action, 0.75, 0.75, 0.75, prefix, "")
    end
end

local function OnUnitCombat(unit, action, flagText, amount, schoolMask)
    if not enabled then
        return
    end

    if unit == "player" then
        HandleIncoming(action, flagText, amount, schoolMask)
    elseif unit == "target" then
        HandleOutgoing(action, flagText, amount, schoolMask)
    end
end

local function RegisterExperimentalEvents()
    local ok, err = pcall(function()
        frame:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
        frame:RegisterEvent("PLAYER_ENTER_COMBAT")
        frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    end)

    if not ok then
        CCL.Print("UNIT_COMBAT adapter registration failed:", tostring(err))
        return false
    end

    return true
end

local function UnregisterExperimentalEvents()
    frame:UnregisterEvent("UNIT_COMBAT")
    frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:UnregisterEvent("PLAYER_ENTER_COMBAT")
    frame:UnregisterEvent("PLAYER_LEAVE_COMBAT")
end

function CCL:EnablePlayerCombatAdapter()
    if enabled then
        self.Print("player-centric UNIT_COMBAT adapter is already enabled.")
        return true
    end

    if not self.AddSecretValueRow then
        self.Print("secret-safe display layer is unavailable.")
        return false
    end

    if not RegisterExperimentalEvents() then
        return false
    end

    enabled = true
    self.Print("experimental player-centric UNIT_COMBAT adapter enabled.")
    self.Print("CLEU remains separate; this branch does not replace or disable the CLEU test.")
    return true
end

function CCL:DisablePlayerCombatAdapter()
    UnregisterExperimentalEvents()
    enabled = false
    playerAutoAttacking = false
    lastPlayerSpellAt = 0
    lastPetSpellAt = 0
    lastPlayerSpellID = nil
    lastPetSpellID = nil
    self.Print("experimental player-centric UNIT_COMBAT adapter disabled.")
end

function CCL:TogglePlayerCombatAdapter()
    if enabled then
        self:DisablePlayerCombatAdapter()
    else
        self:EnablePlayerCombatAdapter()
    end
end

function CCL:IsPlayerCombatAdapterEnabled()
    return enabled
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_COMBAT" then
        OnUnitCombat(...)
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        local now = GetTime()

        if unit == "player" then
            lastPlayerSpellAt = now
            lastPlayerSpellID = spellID
        elseif unit == "pet" then
            lastPetSpellAt = now
            lastPetSpellID = spellID
        end
        return
    end

    if event == "PLAYER_ENTER_COMBAT" then
        playerAutoAttacking = true
        return
    end

    if event == "PLAYER_LEAVE_COMBAT" then
        playerAutoAttacking = false
    end
end)
