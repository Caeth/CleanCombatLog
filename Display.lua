local addonName, CCL = ...

local floor = math.floor
local tooltipStore = {}
local tooltipSerial = 0

local COLORS = {
    red = "|cffaf5050",
    green = "|cff559655",
    lightgreen = "|cff7dcd6e",
    beige = "|cffd7bea5",
    grey = "|cff8c919b",
    reset = "|r",
}

CCL.COLORS = COLORS

local function AddTooltip(text)
    if not text or text == "" then
        return nil
    end

    tooltipSerial = tooltipSerial + 1
    tooltipStore[tooltipSerial] = text

    -- Keep the table bounded during long sessions.
    if tooltipSerial > 5000 then
        tooltipStore[tooltipSerial - 5000] = nil
    end

    return tooltipSerial
end

local function LinkText(text, tooltip)
    local id = AddTooltip(tooltip)
    if not id then
        return text
    end

    return ("|Hccl:%d|h%s|h"):format(id, text)
end

local function OnHyperlinkEnter(self, linkData)
    local id = linkData and linkData:match("^ccl:(%d+)$")
    id = tonumber(id)

    if not id or not tooltipStore[id] then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(tooltipStore[id], 1, 1, 1, true)
    GameTooltip:Show()
end

local function OnHyperlinkLeave()
    GameTooltip:Hide()
end

local function CreateColumn(parent, justify)
    local column = CreateFrame("ScrollingMessageFrame", nil, parent)
    column:SetFontObject(GameFontHighlightSmall)
    column:SetFading(false)
    column:SetMaxLines(250)
    column:SetInsertMode("BOTTOM")
    column:SetJustifyH(justify)
    column:SetJustifyV("BOTTOM")
    column:SetSpacing(1)
    column:SetHyperlinksEnabled(true)
    column:EnableMouseWheel(true)

    column:SetScript("OnHyperlinkEnter", OnHyperlinkEnter)
    column:SetScript("OnHyperlinkLeave", OnHyperlinkLeave)

    return column
end

function CCL:CreateDisplay()
    if self.frame then
        return
    end

    local db = CleanCombatLogDB

    local frame = CreateFrame("Frame", "CleanCombatLogFrame", UIParent)
    self.frame = frame

    frame:SetSize(db.width, db.height)
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        if not CleanCombatLogDB.locked then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CCL:SavePosition()
    end)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.34)
    self.background = background

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", frame, "TOP", 0, -4)
    label:SetText("CleanCombatLog — unlocked")
    self.moveLabel = label

    local top = 20
    local gap = 8

    local incoming = CreateColumn(frame, "RIGHT")
    local info = CreateColumn(frame, "CENTER")
    local outgoing = CreateColumn(frame, "LEFT")

    self.columns = {incoming, info, outgoing}

    local function Layout()
        local width = frame:GetWidth()
        local usable = width - (gap * 2)
        local sideWidth = floor(usable * 0.31)
        local infoWidth = usable - (sideWidth * 2)

        incoming:ClearAllPoints()
        incoming:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
        incoming:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        incoming:SetWidth(sideWidth)

        info:ClearAllPoints()
        info:SetPoint("TOPLEFT", incoming, "TOPRIGHT", gap, 0)
        info:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
        info:SetWidth(infoWidth)

        outgoing:ClearAllPoints()
        outgoing:SetPoint("TOPLEFT", info, "TOPRIGHT", gap, 0)
        outgoing:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end

    self.Layout = Layout
    Layout()

    local function ScrollAll(delta)
        for _, column in ipairs(CCL.columns) do
            if delta > 0 then
                column:ScrollUp()
            else
                column:ScrollDown()
            end
        end
    end

    for _, column in ipairs(self.columns) do
        column:SetScript("OnMouseWheel", function(_, delta)
            ScrollAll(delta)
        end)
    end
end

function CCL:SetChromeVisible(visible)
    if self.background then
        self.background:SetShown(visible)
    end

    if self.moveLabel then
        self.moveLabel:SetShown(visible)
    end
end

function CCL:Clear()
    if not self.columns then
        return
    end

    for _, column in ipairs(self.columns) do
        column:Clear()
    end
end

-- columnIndex: 1 incoming, 2 information, 3 outgoing.
function CCL:AddRow(columnIndex, text, tooltip)
    if not self.columns or not columnIndex or not text then
        return
    end

    local linked = LinkText(tostring(text), tooltip)

    for index, column in ipairs(self.columns) do
        column:AddMessage(index == columnIndex and linked or " ")
        column:ScrollToBottom()
    end
end

function CCL:RunDisplayTest()
    self:Clear()

    local c = COLORS

    self:AddRow(2, c.red .. "++ Combat ++" .. c.reset,
        "Display test: combat begins.")

    self:AddRow(1, "|cffff7f27" .. "237" .. c.reset .. c.beige .. " a" .. c.reset,
        "17:22:01 Training Dummy's Fire Blast hit you for 237 Fire damage. 35 absorbed.")

    self:AddRow(3, c.beige .. "• " .. c.reset .. "|cffff7f27" .. "548" .. c.reset,
        "17:22:02 Your Fireball critically hit Training Dummy for 548 Fire damage.")

    self:AddRow(2, c.green .. "« 350" .. c.reset,
        "17:22:03 Healing received: 350.")

    self:AddRow(1, "|cff69ccf0" .. "Frostbolt ++" .. c.reset,
        "17:22:04 Frostbolt debuff applied to you.")

    self:AddRow(3, c.beige .. "++ " .. c.reset .. "|cff9482c9" .. "Cur" .. c.reset,
        "17:22:05 Your Curse was applied to Training Dummy.")

    self:AddRow(1, c.beige .. "Dodge" .. c.reset,
        "17:22:06 You dodged Training Dummy's melee swing.")

    self:AddRow(2, c.beige .. "†† Training Dummy ††" .. c.reset,
        "17:22:07 Training Dummy died.")

    self:AddRow(2, c.green .. "-- Combat --" .. c.reset,
        "Display test: combat ends.")

    self:AddRow(2, c.red .. "1.2k" .. c.reset .. c.beige .. " ¦ " ..
                   c.red .. "437" .. c.reset .. c.beige .. " ¦ " ..
                   c.green .. "350" .. c.reset,
        "6s in combat\nDamage done: 1200\nDamage received: 437\nHealing received: 350")

    self.Print("display test added. Hover coloured entries for tooltip text.")
end
