local addonName, CCL = ...

-- Experimental display path for Midnight/Forever Secret Values.
-- It deliberately avoids tostring(), concatenation, arithmetic, or comparison on
-- the combat amount itself. Values are passed directly to FontString:SetText().

local ROW_COUNT = 14
local ROW_HEIGHT = 14

local function CreateCell(parent, justify)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetHeight(ROW_HEIGHT)

    local value = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local prefix = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local suffix = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    if justify == "RIGHT" then
        value:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
        prefix:SetPoint("RIGHT", value, "LEFT", -2, 0)
        suffix:SetPoint("LEFT", value, "RIGHT", 2, 0)
        value:SetJustifyH("RIGHT")
    elseif justify == "LEFT" then
        prefix:SetPoint("LEFT", cell, "LEFT", 0, 0)
        value:SetPoint("LEFT", prefix, "RIGHT", 2, 0)
        suffix:SetPoint("LEFT", value, "RIGHT", 2, 0)
        value:SetJustifyH("LEFT")
    else
        value:SetPoint("CENTER", cell, "CENTER", 0, 0)
        prefix:SetPoint("RIGHT", value, "LEFT", -2, 0)
        suffix:SetPoint("LEFT", value, "RIGHT", 2, 0)
        value:SetJustifyH("CENTER")
    end

    return {
        frame = cell,
        prefix = prefix,
        value = value,
        suffix = suffix,
    }
end

local function ClearCell(cell)
    cell.prefix:SetText("")
    cell.value:SetText("")
    cell.suffix:SetText("")
end

function CCL:CreateSecretDisplay()
    if self.secretRows or not self.columns then
        return
    end

    self.secretRows = {}

    for rowIndex = 1, ROW_COUNT do
        local row = {
            CreateCell(self.columns[1], "RIGHT"),
            CreateCell(self.columns[2], "CENTER"),
            CreateCell(self.columns[3], "LEFT"),
        }

        for columnIndex, cell in ipairs(row) do
            cell.frame:SetPoint("LEFT", self.columns[columnIndex], "LEFT", 0, 0)
            cell.frame:SetPoint("RIGHT", self.columns[columnIndex], "RIGHT", 0, 0)
            cell.frame:SetPoint("BOTTOM", self.columns[columnIndex], "BOTTOM", 0, (rowIndex - 1) * ROW_HEIGHT)
            ClearCell(cell)
        end

        self.secretRows[rowIndex] = row
    end
end

function CCL:ClearSecretRows()
    if not self.secretRows then
        return
    end

    for _, row in ipairs(self.secretRows) do
        for _, cell in ipairs(row) do
            ClearCell(cell)
        end
    end
end

local function RepositionRows(rows)
    for rowIndex, row in ipairs(rows) do
        for _, cell in ipairs(row) do
            cell.frame:ClearAllPoints()
        end

        for columnIndex, cell in ipairs(row) do
            local column = CCL.columns[columnIndex]
            cell.frame:SetPoint("LEFT", column, "LEFT", 0, 0)
            cell.frame:SetPoint("RIGHT", column, "RIGHT", 0, 0)
            cell.frame:SetPoint("BOTTOM", column, "BOTTOM", 0, (rowIndex - 1) * ROW_HEIGHT)
        end
    end
end

-- columnIndex: 1 incoming, 2 information/recovery, 3 outgoing.
-- value may be a Secret Value. Do not inspect or transform it before calling here.
function CCL:AddSecretValueRow(columnIndex, value, r, g, b, prefixText, suffixText)
    if not self.secretRows or not self.secretRows[1] then
        return
    end

    local row = table.remove(self.secretRows, 1)

    for _, cell in ipairs(row) do
        ClearCell(cell)
    end

    table.insert(self.secretRows, row)
    RepositionRows(self.secretRows)

    local cell = row[columnIndex]
    if not cell then
        return
    end

    cell.prefix:SetText(prefixText or "")
    cell.suffix:SetText(suffixText or "")
    cell.value:SetText(value)
    cell.value:SetTextColor(r or 1, g or 1, b or 1)
end

local originalCreateDisplay = CCL.CreateDisplay
function CCL:CreateDisplay()
    originalCreateDisplay(self)
    self:CreateSecretDisplay()
end

local originalClear = CCL.Clear
function CCL:Clear()
    originalClear(self)
    self:ClearSecretRows()
end
