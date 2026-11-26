local addonName, CCL = ...

CCL = CCL or {}
_G.CleanCombatLog = CCL

CCL.name = addonName or "CleanCombatLog"
CCL.version = "0.3.0"

local function Print(...)
    print("|cff7dcde6CleanCombatLog:|r", ...)
end

CCL.Print = Print

local function CanAccess(v)
    if canaccessvalue then
        local ok, accessible = pcall(canaccessvalue, v)
        if not ok or not accessible then return false end
    end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return false end
    end
    if issecrettable and type(v) == "table" then
        local ok, secret = pcall(issecrettable, v)
        if not ok or secret then return false end
    end
    return true
end
CCL.CanAccess = CanAccess

local defaults = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -180,
    width = 520,
    height = 220,
    locked = false,
}

local function ApplyDefaults(db, src)
    for key, value in pairs(src) do
        if db[key] == nil then
            db[key] = value
        end
    end
end

function CCL:GetCurrentCombatLogEventInfo()
    if C_CombatLog and C_CombatLog.GetCurrentEventInfo then
        return C_CombatLog.GetCurrentEventInfo()
    end

    if CombatLogGetCurrentEventInfo then
        return CombatLogGetCurrentEventInfo()
    end
end

function CCL:GetCombatLogAPIMode()
    if C_CombatLog and C_CombatLog.GetCurrentEventInfo then
        return "C_CombatLog.GetCurrentEventInfo"
    elseif CombatLogGetCurrentEventInfo then
        return "CombatLogGetCurrentEventInfo"
    end

    return nil
end

function CCL:IsForeverClient()
    return WOW_PROJECT_ID ~= nil
        and (WOW_PROJECT_ID == WOW_PROJECT_CAMELOT or WOW_PROJECT_ID == 18)
end

function CCL:PrintAPIReport()
    local version, build, buildDate, interfaceVersion = GetBuildInfo()

    Print("version:", self.version)
    Print("client:", version or "?", "build:", build or "?", "interface:", interfaceVersion or "?")
    Print("WOW_PROJECT_ID:", tostring(WOW_PROJECT_ID))
    Print("WOW_PROJECT_CAMELOT:", tostring(WOW_PROJECT_CAMELOT), "Forever project:", tostring(self:IsForeverClient()))
    Print("combat-log payload API:", self:GetCombatLogAPIMode() or "NOT FOUND")
    Print("C_CombatText.GetCurrentEventInfo:", tostring(C_CombatText and C_CombatText.GetCurrentEventInfo ~= nil))
    Print("C_DamageMeter present:", tostring(C_DamageMeter ~= nil))
    Print("C_DeathRecap present:", tostring(C_DeathRecap ~= nil))
    Print("COMBAT_LOG_EVENT_UNFILTERED registered:", self.CombatLog and tostring(self.CombatLog:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")) or "false")
    Print("Experimental UNIT_COMBAT adapter enabled:", tostring(self:IsPlayerCombatAdapterEnabled()))
    Print("Use |cffffffff/ccl probe start|r for the Forever event/API instrumentation pass.")
end

function CCL:SavePosition()
    if not self.frame or not CleanCombatLogDB then
        return
    end

    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    CleanCombatLogDB.point = point
    CleanCombatLogDB.relativePoint = relativePoint
    CleanCombatLogDB.x = x
    CleanCombatLogDB.y = y
    CleanCombatLogDB.width = self.frame:GetWidth()
    CleanCombatLogDB.height = self.frame:GetHeight()
end

function CCL:SetLocked(locked)
    CleanCombatLogDB.locked = locked and true or false

    if self.frame then
        self.frame:SetMovable(not CleanCombatLogDB.locked)
        if self.SetChromeVisible then
            self:SetChromeVisible(not CleanCombatLogDB.locked)
        end
    end

    Print(CleanCombatLogDB.locked and "frame locked." or "frame unlocked; drag the dark background to move it.")
end

local function OnAddonLoaded(_, event, loadedAddon)
    if loadedAddon ~= addonName then
        return
    end

    CleanCombatLogDB = CleanCombatLogDB or {}
    ApplyDefaults(CleanCombatLogDB, defaults)

    if CCL.CreateDisplay then
        CCL:CreateDisplay()
    end
    if CCL.InitializePersonalFeed then
        CCL:InitializePersonalFeed()
    end

    CCL:SetLocked(CleanCombatLogDB.locked)

    Print("loaded. Type |cffffffff/ccl help|r for commands.")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", OnAddonLoaded)

SLASH_CLEANCOMBATLOG1 = "/ccl"
SlashCmdList.CLEANCOMBATLOG = function(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()

    if command == "" or command == "help" then
        Print("commands:")
        Print("/ccl test        - add representative dummy rows")
        Print("/ccl api         - print client/API diagnostics")
        Print("/ccl cleu        - attempt/toggle COMBAT_LOG_EVENT_UNFILTERED")
        Print("/ccl unitcombat  - toggle the experimental UNIT_COMBAT adapter")
        Print("/ccl probe ...   - Forever combat API instrumentation")
        Print("/ccl feed [on|off] - show status or toggle the personal feed")
        Print("/ccl clear       - clear all three columns")
        Print("/ccl lock        - lock the display")
        Print("/ccl move        - unlock/move the display")
        return
    end

    if command == "test" then
        if CCL.RunDisplayTest then
            CCL:RunDisplayTest()
        end
    elseif command == "api" then
        CCL:PrintAPIReport()
    elseif command == "cleu" then
        if CCL.ToggleCLEU then
            CCL:ToggleCLEU()
        else
            Print("combat-log module has not loaded.")
        end
    elseif command == "unitcombat" then
        CCL:TogglePlayerCombatAdapter()
    elseif command == "feed" then
        CCL:HandlePersonalFeedCommand(rest)
    elseif command == "probe" then
        if CCL.HandleProbeCommand then
            CCL:HandleProbeCommand(rest)
        else
            Print("combat probe module has not loaded.")
        end
    elseif command == "clear" then
        if CCL.Clear then
            CCL:Clear()
        end
    elseif command == "lock" then
        CCL:SetLocked(true)
    elseif command == "move" or command == "unlock" then
        CCL:SetLocked(false)
    else
        Print("unknown command:", command, "- use /ccl help")
    end
end
