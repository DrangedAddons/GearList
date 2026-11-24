---------------------------------------------------------
--  GearList - the checklist window
--  Author: Dranged
---------------------------------------------------------
-- Two views, picked by the tabs:
--   Gear: one line per slot. Slot, item, an icon for the kind of source, the
--     details (where it is or comes from), what it costs, the reputation it
--     needs, and its enchant. Click a column's name to sort by it; Slot puts
--     the character-sheet order back. Right-click a column's name to filter.
--   Dungeons: the missing items by dungeon, most items first, then by boss.
-- On both, what you can get where you're standing (the dungeon you're in, or
-- the zone) is washed blue.

local ADDON, NS = ...
local UI = NS.UI

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local WIDTH, ROW_H, ROWS = 1004, 20, 17
local HEAD_H = 16
-- x of each column inside a row
local COL = { slot = 4, tick = 68, icon = 84, name = 104, src = 290, info = 344, cost = 510, rep = 636, etick = 770, ench = 786 }
-- column, its name, and where its clickable header ends
local HEADERS = { { "slot", "Slot", "name" }, { "name", "Item", "src" }, { "src", "Source", "info" },
    { "info", "Details", "cost" }, { "cost", "Cost", "rep" }, { "rep", "Reputation", "etick" }, { "ench", "Enchant" } }
-- Sorting by source: drops together, then quests, vendors, crafted, bought.
local KIND_RANK = { drop = 1, chest = 2, world = 3, quest = 4, vendor = 5, currency = 6, craft = 7, auction = 8 }
-- The Dungeons view's columns
local DCOL = { boss = 24, icon = 300, name = 320, slot = 640 }
local DHEADERS = { { "boss", "Boss" }, { "name", "Item" }, { "slot", "Slot" } }

local frame, list, dlist, empty, deleteBtn
local headers = { gear = {}, dungeons = {} } -- each view's column names
local hereNames = {} -- where you are (NS.Here), read at each refresh; empty for another character's list
local view = { char = nil, set = nil } -- whose list, and which one, is on screen

---------------------------------------------------------
--  SECTION: What's on screen
---------------------------------------------------------
local function Resolve()
    if not view.char or not NS.db.chars[view.char] then view.char = NS.playerKey end
    local set = NS.FindSet(view.char, view.set)
        or NS.FindSet(view.char, NS.db.active[view.char])
        or NS.SetsFor(view.char)[1]
    view.set = set and set.name or nil
    return set
end

local function Own() return view.char == NS.playerKey end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- The item's name in its quality colour (the export's name until the game has it), and its link.
local function ItemText(e)
    local name, link, quality = GetInfo(e.id)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.id) end
        return e.name, nil
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return ((color and color.hex) or "|cffffffff") .. name .. "|r", link
end

local function ItemIcon(id)
    local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return (fn and fn(id)) or QUESTION
end

---------------------------------------------------------
--  SECTION: Rows
---------------------------------------------------------
local function AddSourceLines(src)
    if not src or #src.tip == 0 then return false end
    GameTooltip:AddLine(" ")
    for _, line in ipairs(src.tip) do
        if line[2] then
            GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine(line[1], 1, 1, 1, true)
        end
    end
    return true
end

local function RowEnter(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, e.id) then GameTooltip:SetText(e.name, 1, 1, 1) end
    if not AddSourceLines(NS.ItemSource(e.id, Own())) and not NS.ItemDone(e) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("No source on record. If a vendor sells it, its price is written down when you open that vendor.",
            0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Right-click|r to tick or untick by hand", 1, 1, 1)
    GameTooltip:AddLine("|cffffd100Shift-click|r to link, |cffffd100Ctrl-click|r to try on", 1, 1, 1)
    GameTooltip:Show()
end

local function EnchEnter(hit)
    local e = hit:GetParent().item
    if not (e and e.ench) then return end
    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
    local ok = e.ench.spell and pcall(GameTooltip.SetSpellByID, GameTooltip, e.ench.spell)
    if not ok or GameTooltip:NumLines() == 0 then GameTooltip:SetText(e.ench.name, 1, 1, 1) end
    AddSourceLines(NS.EnchSource(e, Own()))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Right-click|r to tick or untick by hand", 1, 1, 1)
    GameTooltip:Show()
end

local function EnchClick(hit, mouse)
    local e = hit:GetParent().item
    if not (e and e.ench) then return end
    if mouse == "RightButton" then
        e.emark = (not e.emark) or nil
        NS.Changed()
    elseif IsModifiedClick and IsModifiedClick("CHATLINK") and e.ench.spell and ChatEdit_InsertLink then
        local GetLink = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
        local link = GetLink and GetLink(e.ench.spell)
        if link then ChatEdit_InsertLink(link) end
    end
end

local function Tint(tex, found)
    if found then tex:SetColorTexture(0.2, 1, 0.3, 0.14) else tex:SetColorTexture(1, 0.82, 0, 0.12) end
end

-- The list's plain rows get the checklist's columns.
local function Decorate(row)
    row.gearListRow = true
    -- Faint tints behind the item half and the enchant half, on once you have that half.
    -- A finished row is tinted right across. 1 px is left clear between rows.
    row.have = row:CreateTexture(nil, "BACKGROUND")
    row.have:SetPoint("TOPLEFT", 0, -1)
    row.have:SetPoint("BOTTOMLEFT", 0, 1)
    row.have:SetWidth(COL.etick - 6)
    -- A blue wash and edge on a row you can get where you're standing.
    row.here = row:CreateTexture(nil, "BACKGROUND")
    row.here:SetPoint("TOPLEFT", 0, -1)
    row.here:SetPoint("BOTTOMRIGHT", 0, 1)
    row.here:SetColorTexture(0.25, 0.6, 1, 0.2)
    row.hereBar = row:CreateTexture(nil, "BORDER")
    row.hereBar:SetPoint("TOPLEFT", 0, -1)
    row.hereBar:SetPoint("BOTTOMLEFT", 0, 1)
    row.hereBar:SetWidth(3)
    row.hereBar:SetColorTexture(0.35, 0.75, 1, 1)
    row.ehave = row:CreateTexture(nil, "BACKGROUND")
    row.ehave:SetPoint("TOPLEFT", COL.etick - 6, -1)
    row.ehave:SetPoint("BOTTOMRIGHT", 0, 1)
    row.slot = UI.Text(row, "", "GameFontDisableSmall")
    row.slot:SetPoint("LEFT", COL.slot, 0)
    row.slot:SetWidth(COL.tick - COL.slot - 2)
    row.slot:SetWordWrap(false)

    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetSize(12, 12)
    row.tick:SetPoint("LEFT", COL.tick, 0)

    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", COL.icon, 0)
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", COL.name, 0)
    row.text:SetWidth(COL.src - COL.name - 6)

    -- Source: an icon for the kind (boss, quest, vendor, profession...), under the column's name.
    row.sicon = row:CreateTexture(nil, "ARTWORK")
    row.sicon:SetSize(14, 14)
    row.sicon:SetPoint("LEFT", COL.src + 12, 0)
    -- Details: where the item is, or where it comes from while it's missing.
    row.info = UI.Text(row, "", "GameFontHighlightSmall")
    row.info:SetPoint("LEFT", COL.info, 0)
    row.info:SetWidth(COL.cost - COL.info - 6)
    row.info:SetWordWrap(false)

    -- Gold or token amounts, and the reputation it needs.
    row.cost = UI.Text(row, "", "GameFontHighlightSmall")
    row.cost:SetPoint("LEFT", COL.cost, 0)
    row.cost:SetWidth(COL.rep - COL.cost - 6)
    row.cost:SetWordWrap(false)
    row.rep = UI.Text(row, "", "GameFontHighlightSmall")
    row.rep:SetPoint("LEFT", COL.rep, 0)
    row.rep:SetWidth(COL.etick - COL.rep - 8)
    row.rep:SetWordWrap(false)

    row.etick = row:CreateTexture(nil, "ARTWORK")
    row.etick:SetSize(12, 12)
    row.etick:SetPoint("LEFT", COL.etick, 0)

    row.ench = UI.Text(row, "", "GameFontHighlightSmall")
    row.ench:SetPoint("LEFT", COL.ench, 0)
    row.ench:SetPoint("RIGHT", -4, 0)
    row.ench:SetWordWrap(false)

    -- The enchant half has its own tooltip and its own hand tick.
    row.enchHit = CreateFrame("Button", nil, row)
    row.enchHit:SetPoint("TOPLEFT", COL.etick - 4, 0)
    row.enchHit:SetPoint("BOTTOMRIGHT", 0, 0)
    row.enchHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.enchHit:SetScript("OnEnter", EnchEnter)
    row.enchHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.enchHit:SetScript("OnClick", EnchClick)

    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Render(row, e)
    local own = Own()
    local name, link = ItemText(e)
    row.link = link
    row.icon:SetTexture(ItemIcon(e.id))
    row.icon:Show()
    row.text:SetText(name)
    row.slot:SetText(NS.SlotLabel(e.slot))

    local done = NS.ItemDone(e)
    row.tick:SetTexture(done and READY or NOTREADY)
    row.tick:SetAlpha(done and 1 or 0.7)
    -- Green for what the game found, gold for a hand tick.
    row.have:SetShown(done)
    if e.st then Tint(row.have, true) elseif done then Tint(row.have, false) end
    local enchDone = e.ench and NS.EnchDone(e)
    row.ehave:SetShown(done and (not e.ench or enchDone) or false)
    if e.ench then Tint(row.ehave, e.est == true) else Tint(row.ehave, e.st ~= nil) end
    row.cost:SetText("")
    row.rep:SetText("")
    row.sicon:Hide()
    row.here:Hide()
    row.hereBar:Hide()
    if e.st == "equipped" then
        row.info:SetText("Equipped"); row.info:SetTextColor(0.3, 1, 0.3)
    elseif e.st == "bags" then
        row.info:SetText("In bags"); row.info:SetTextColor(0.3, 1, 0.3)
    elseif e.st == "bank" then
        row.info:SetText("In bank"); row.info:SetTextColor(0.3, 1, 0.3)
    elseif e.mark then
        row.info:SetText("Ticked"); row.info:SetTextColor(1, 0.82, 0)
    else
        local src = NS.ItemSource(e.id, own)
        if #src.parts > 0 then
            row.info:SetText(table.concat(src.parts, "  |  ")); row.info:SetTextColor(0.85, 0.85, 0.85)
        else
            row.info:SetText("Missing"); row.info:SetTextColor(1, 0.4, 0.4)
        end
        if src.icon then
            row.sicon:SetTexture(src.icon)
            row.sicon:Show()
        end
        row.cost:SetText(src.cost or "")
        row.rep:SetText(src.rep or "")
        local here = NS.IsHere(src.places, hereNames)
        row.here:SetShown(here)
        row.hereBar:SetShown(here)
    end

    row.enchHit:SetShown(e.ench ~= nil)
    if not e.ench then
        row.etick:Hide()
        row.ench:SetText("")
        return
    end
    row.etick:Show()
    -- "Enchant Bracer - Healing Power" reads fine without its first word; the tooltip has it whole.
    row.ench:SetText((e.ench.name:gsub("^Enchant ", "")))
    if NS.EnchDone(e) then
        row.etick:SetTexture(READY); row.etick:SetAlpha(1)
        if e.est == true then row.ench:SetTextColor(0.3, 1, 0.3) else row.ench:SetTextColor(1, 0.82, 0) end
    elseif e.st == "bank" then
        -- The game doesn't say what's on an item in the bank.
        row.etick:SetTexture(WAITING); row.etick:SetAlpha(1)
        row.ench:SetTextColor(1, 1, 1)
    else
        row.etick:SetTexture(NOTREADY); row.etick:SetAlpha(done and 0.9 or 0.35)
        if done then row.ench:SetTextColor(1, 1, 1) else row.ench:SetTextColor(0.6, 0.6, 0.6) end
    end
end

local function RowClick(_, e, mouse)
    if mouse == "RightButton" then
        e.mark = (not e.mark) or nil
        NS.Changed()
        return
    end
    local _, link = GetInfo(e.id)
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

---------------------------------------------------------
--  SECTION: Delete prompt
---------------------------------------------------------
StaticPopupDialogs["GEARLIST_DELETE"] = {
    text = "Delete the gear list \"%s\" for %s?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data)
        if data then NS.DeleteSet(data.char, data.set) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

---------------------------------------------------------
--  SECTION: Dungeons view
---------------------------------------------------------
local function DungeonEnter(row)
    local d = row.item
    if not (d and d.e) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, d.e.id) then GameTooltip:SetText(d.e.name, 1, 1, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Shift-click|r to link, |cffffd100Ctrl-click|r to try on", 1, 1, 1)
    GameTooltip:Show()
end

local function DecorateDungeon(row)
    row.gearListRow = true
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints()
    row.band:SetColorTexture(1, 1, 1, 0.07)
    row.boss = UI.Text(row, "", "GameFontHighlightSmall")
    row.boss:SetPoint("LEFT", DCOL.boss, 0)
    row.boss:SetWidth(DCOL.icon - DCOL.boss - 8)
    row.boss:SetWordWrap(false)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", DCOL.icon, 0)
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.slot = UI.Text(row, "", "GameFontDisableSmall")
    row.slot:SetPoint("LEFT", DCOL.slot, 0)
    row.count = UI.Text(row, "", "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnEnter", DungeonEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function RenderDungeon(row, d)
    row.text:ClearAllPoints()
    if d.e then
        -- A boss's name shows on its first item only. Blue when it's the dungeon you're in.
        row.band:SetShown(d.here == true)
        row.band:SetColorTexture(0.25, 0.6, 1, 0.14)
        row.boss:SetText(d.first and d.who or "")
        row.icon:SetTexture(ItemIcon(d.e.id))
        row.icon:Show()
        row.text:SetPoint("LEFT", DCOL.name, 0)
        row.text:SetWidth(DCOL.slot - DCOL.name - 8)
        row.text:SetText((ItemText(d.e)))
        row.slot:SetText(NS.SlotLabel(d.e.slot))
        row.count:SetText("")
        return
    end
    row.icon:Hide()
    row.boss:SetText("")
    row.slot:SetText("")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetWidth(WIDTH - 200)
    if d.dungeon then
        row.band:Show()
        if d.here then row.band:SetColorTexture(0.25, 0.6, 1, 0.3) else row.band:SetColorTexture(1, 1, 1, 0.07) end
        row.text:SetText("|cffffd100" .. d.dungeon .. "|r" .. (d.here and "   |cff66bbffyou are here|r" or ""))
        row.count:SetText(d.count .. (d.count == 1 and " item" or " items"))
    else
        row.band:Hide()
        row.text:SetText("|cff9d9d9d" .. d.note .. "|r")
        row.count:SetText("")
    end
end

local function DungeonClick(_, d)
    if not d.e then return end
    local _, link = GetInfo(d.e.id)
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

---------------------------------------------------------
--  SECTION: Window
---------------------------------------------------------
local function CurrentTab()
    return NS.db.tab == "dungeons" and "dungeons" or "gear"
end

-- A flat tab; the two of them swap the whole view.
local function Tab(parent, text, width, key)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    UI.Backdrop(b, 0.1, 0.1, 0.11, 1)
    b.text = UI.Text(b, text, "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetPoint("BOTTOMLEFT", 1, 1)
    b.line:SetPoint("BOTTOMRIGHT", -1, 1)
    b.line:SetHeight(2)
    b:SetScript("OnClick", function()
        NS.db.tab = key
        UI.RefreshAll()
    end)
    function b:Refresh()
        local on = CurrentTab() == key
        self.line:SetColorTexture(NS.AccentColor())
        self.line:SetShown(on)
        if on then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(0.6, 0.6, 0.6) end
    end
    return UI.Track(b)
end

---------------------------------------------------------
--  SECTION: Sorting
---------------------------------------------------------
-- What a row sorts on for a column: { nothing there, key, key, ... }. Rows with
-- nothing in that column go last whichever way the sort runs.
local function SortKeys(e, key, own)
    if key == "name" then return { false, e.name:lower() } end
    if key == "ench" then return { e.ench == nil, e.ench and e.ench.name:lower() or "" } end
    -- Source, details, cost and reputation only show on rows still to get.
    if NS.ItemDone(e) then return { true } end
    local src = NS.ItemSource(e.id, own)
    if key == "src" then
        return { src.kind == nil, KIND_RANK[src.kind] or 99, (src.parts[1] or ""):lower() }
    elseif key == "info" then
        return { #src.parts == 0, table.concat(src.parts, " "):lower() }
    elseif key == "cost" then
        -- Currencies by name, then token items, then gold; dearest first within each.
        local c = src.costSort
        return { c == nil, c and c[1] or 9, c and c[2]:lower() or "", c and -c[3] or 0 }
    elseif key == "rep" then
        local text = src.rep and src.rep:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
        return { text == nil, text or "" }
    end
    return { true }
end

-- Sorts the rows in place. "slot" is the list's own order: nothing to do.
local function SortRows(data, own)
    local key, desc = NS.db.sortKey, NS.db.sortDesc
    if key == nil or key == "slot" then return end
    local rows = {}
    for i, e in ipairs(data) do rows[i] = { e = e, i = i, k = SortKeys(e, key, own) } end
    table.sort(rows, function(a, b)
        local ka, kb = a.k, b.k
        if ka[1] ~= kb[1] then return kb[1] end
        for n = 2, math.max(#ka, #kb) do
            local x, y = ka[n], kb[n]
            if x ~= y and x ~= nil and y ~= nil then
                if desc then return x > y end
                return x < y
            end
        end
        return a.i < b.i -- equal: keep the sheet order
    end)
    for i, r in ipairs(rows) do data[i] = r.e end
end

local function SetSort(key)
    local db = NS.db
    if key == "slot" then
        db.sortKey, db.sortDesc = "slot", false -- always back to the normal order
    elseif db.sortKey == key then
        db.sortDesc = not db.sortDesc
    else
        db.sortKey, db.sortDesc = key, false
    end
    list:ScrollTo(0)
    UI.RefreshAll()
end

---------------------------------------------------------
--  SECTION: Filters
---------------------------------------------------------
-- One choice per column, picked from the menu a right-click on its name opens.
-- Columns combine: a row has to pass every one that's set. Not saved, so the
-- list is whole again after a reload.
local filters = {} -- column -> the chosen value

local SLOT_GROUP = {
    NECK = "jewel", FINGER_1 = "jewel", FINGER_2 = "jewel", TRINKET_1 = "jewel", TRINKET_2 = "jewel",
    MAIN_HAND = "weapon", OFF_HAND = "weapon", RANGED = "weapon", AMMO = "weapon",
}
local KIND_NAME = {
    drop = "Boss and creature drops", chest = "Chests", world = "World drops", quest = "Quests",
    vendor = "Vendors", currency = "Currency vendors", craft = "Crafted", auction = "Bought (BoE)",
}
local KIND_LIST = { "drop", "chest", "world", "quest", "vendor", "currency", "craft", "auction" }

-- The place a source starts with: "Stratholme" in "Stratholme, Ramstein the Gorger".
-- Only drops, chests and vendors are written place first; a quest's or item's own
-- comma isn't a place.
local PLACED = { drop = true, chest = true, vendor = true }
local function PlaceOf(src, n)
    return PLACED[src.kinds[n]] and src.parts[n]:match("^(.-), ") or nil
end

local function Passes(e, key, want, own)
    if key == "slot" then return (SLOT_GROUP[e.slot] or "armor") == want end
    if key == "name" then return NS.ItemDone(e) == (want == "have") end
    if key == "ench" then
        if want == "none" then return e.ench == nil end
        return e.ench ~= nil and NS.EnchDone(e) == (want == "done")
    end
    -- The rest are about getting the item, so a row you already have never passes.
    if NS.ItemDone(e) then return false end
    local src = NS.ItemSource(e.id, own)
    if key == "src" then
        if want == "none" then return src.kind == nil end
        return src.kind == want
    elseif key == "info" then
        for n in ipairs(src.parts) do
            if PlaceOf(src, n) == want then return true end
        end
        return false
    elseif key == "cost" then
        local c = src.costSort
        if want == "any" then return src.cost ~= nil end
        if want == "gold" then return c ~= nil and c[1] == 3 end
        return c ~= nil and c[1] ~= 3 and c[2] == want
    elseif key == "rep" then
        if want == "any" then return src.rep ~= nil end
        for _, q in ipairs(src.reqs or {}) do
            if q.kind == "rep" and q.a == want then return true end
        end
        return false
    end
    return true
end

local function PassesAll(e, own)
    for key, want in pairs(filters) do
        if not Passes(e, key, want, own) then return false end
    end
    return true
end

-- The menu for a column: All, then the choices this list actually has rows for.
local function FilterOptions(key, set, own)
    local items = { { value = false, label = "All" } }
    local function Add(value, label) items[#items + 1] = { value = value, label = label } end
    if next(filters) then Add("@clear", "|cffffd100Clear every filter|r") end
    if key == "slot" then
        Add("armor", "Armor"); Add("jewel", "Neck, rings and trinkets"); Add("weapon", "Weapons and relics")
    elseif key == "name" then
        Add("missing", "Still to get"); Add("have", "Have it")
    elseif key == "ench" then
        Add("todo", "Enchant still to do"); Add("done", "Enchant done"); Add("none", "No enchant listed")
    else
        -- Collect what the rows still to get have in this column.
        local seen, names = {}, {}
        local function Seen(value)
            if value and not seen[value] then
                seen[value] = true
                names[#names + 1] = value
            end
        end
        local any = false
        for _, e in ipairs(set and set.items or {}) do
            if not NS.ItemDone(e) then
                local src = NS.ItemSource(e.id, own)
                if key == "src" then
                    Seen(src.kind or "none")
                elseif key == "info" then
                    for n in ipairs(src.parts) do Seen(PlaceOf(src, n)) end
                elseif key == "cost" and src.costSort then
                    any = true
                    Seen(src.costSort[1] == 3 and "gold" or src.costSort[2])
                elseif key == "rep" then
                    for _, q in ipairs(src.reqs or {}) do
                        if q.kind == "rep" then any = true; Seen(q.a) end
                    end
                end
            end
        end
        if key == "src" then
            for _, kind in ipairs(KIND_LIST) do
                if seen[kind] then Add(kind, KIND_NAME[kind]) end
            end
            if seen.none then Add("none", "No source on record") end
        else
            if any then Add("any", key == "cost" and "Anything with a cost" or "Anything needing reputation") end
            table.sort(names)
            for _, name in ipairs(names) do
                if name == "gold" and key == "cost" then Add("gold", "Gold") else Add(name, name) end
            end
        end
    end
    return items
end

local function SetFilter(key, value)
    if value == "@clear" then
        for k in pairs(filters) do filters[k] = nil end
    else
        filters[key] = value or nil
    end
    list:ScrollTo(0)
    UI.RefreshAll()
end

-- A column name. Click sorts by it (an arrow marks the sorted one); right-click
-- opens its filter menu (a tick marks a filtered one).
local function Header(parent, key, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, HEAD_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = UI.Text(b, text, "GameFontDisableSmall")
    b.text:SetPoint("LEFT", 0, 0)
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.mark:SetSize(12, 12)
    b.mark:SetPoint("LEFT", b.text, "RIGHT", 1, 0)
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    b.arrow:SetSize(9, 8)
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            UI.OpenMenu(self, FilterOptions(key, Resolve(), Own()), filters[key] or false, function(v) SetFilter(key, v) end)
        else
            SetSort(key)
        end
    end)
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(text, 1, 0.82, 0)
        GameTooltip:AddLine(key == "slot" and "|cffffd100Click|r for the normal order" or "|cffffd100Click|r to sort, again to reverse", 1, 1, 1)
        GameTooltip:AddLine("|cffffd100Right-click|r to filter", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:Refresh()
    end)
    function b:Refresh()
        local on = (NS.db.sortKey or "slot") == key
        local filtered = filters[key] ~= nil
        if on then self.text:SetTextColor(NS.AccentColor()) else self.text:SetTextColor(0.5, 0.5, 0.5) end
        self.mark:SetShown(filtered)
        -- Slot is the resting order, so it gets no arrow.
        self.arrow:SetShown(on and key ~= "slot")
        self.arrow:ClearAllPoints()
        self.arrow:SetPoint("LEFT", filtered and self.mark or self.text, "RIGHT", 3, 0)
        if NS.db.sortDesc then self.arrow:SetTexCoord(0, 0.5625, 0, 1) else self.arrow:SetTexCoord(0, 0.5625, 1, 0) end
    end
    return UI.Track(b)
end

local function Refresh()
    if not frame:IsShown() then return end
    local set = Resolve()
    local own = Own()
    deleteBtn:SetEnabled(set ~= nil)
    -- Another character's list shows what was found the last time you were on it.
    local title = "Gear List"
    if set and not own then
        title = title .. ": " .. NS.CharName(view.char) .. (set.scanned
            and (", as of " .. date("%d %b %H:%M", set.scanned))
            or ", not checked on that character yet")
    end
    -- On your own list: how much of it you can get where you are.
    hereNames = own and NS.Here() or {}
    if set and own and #hereNames > 0 then
        local n = 0
        for _, e in ipairs(set.items) do
            if not NS.ItemDone(e) and NS.IsHere(NS.ItemSource(e.id, true).places, hereNames) then n = n + 1 end
        end
        if n > 0 then
            title = title .. ": " .. n .. (n == 1 and " item" or " items") .. " to get in " .. hereNames[1]
        end
    end
    frame.nsTitle:SetText(title)

    local tab = CurrentTab()
    list:SetShown(tab == "gear")
    dlist:SetShown(tab == "dungeons")
    for key, labels in pairs(headers) do
        for _, label in ipairs(labels) do label:SetShown(key == tab and set ~= nil) end
    end
    if not set then
        list:SetData({})
        dlist:SetData({})
        empty:SetText("No gear list for " .. NS.CharName(view.char) .. " yet.\n\n"
            .. "Build a set at |cffffd100sixtyupgrades.com/forever|r, click Export there and copy the text.\n"
            .. "Then click |cffffd100Import|r here and paste it.")
        empty:Show()
        return
    end
    empty:Hide()

    if tab == "dungeons" then
        local rows, others = NS.DungeonRows(set)
        -- The dungeon you're in, and everything under it.
        local inHere = false
        for _, r in ipairs(rows or {}) do
            if r.dungeon then inHere = NS.IsHere({ r.dungeon }, hereNames) end
            r.here = inHere or nil
        end
        if not rows then
            rows = {}
            empty:SetText("Dungeon drops come from the DungeonJournal addon, and it isn't loaded.")
            empty:Show()
        elseif #rows == 0 then
            empty:SetText("None of the missing items drop in a dungeon.")
            empty:Show()
        elseif others > 0 then
            rows[#rows + 1] = { note = others .. (others == 1 and " more missing item doesn't" or " more missing items don't")
                .. " come from a dungeon. See the Gear tab." }
        end
        dlist:SetData(rows)
        return
    end

    local data = {}
    for _, e in ipairs(set.items) do
        local finished = NS.ItemDone(e) and (not e.ench or NS.EnchDone(e))
        if (NS.db.showDone or not finished) and PassesAll(e, own) then data[#data + 1] = e end
    end
    SortRows(data, own)
    list:SetData(data)
    if #data == 0 then
        empty:SetText(next(filters)
            and "Nothing matches the filters.\nRight-click a column's name to change them, or pick Clear every filter."
            or "Every slot on this list is done.")
        empty:Show()
    end
end

local function Build()
    local db = NS.db
    local bodyW = WIDTH - 36
    local listH = ROWS * ROW_H + 4
    frame = UI.Window({ name = "GearListFrame", title = "Gear List", width = WIDTH, height = 44 + 26 + HEAD_H + listH + 16 })
    local body = frame.body

    -- Row 1: the view's tabs on the left, whose list on the right.
    local gearTab = Tab(body, "Gear", 80, "gear")
    gearTab:SetPoint("TOPLEFT", 0, 0)
    local dungeonTab = Tab(body, "Dungeons", 90, "dungeons")
    dungeonTab:SetPoint("LEFT", gearTab, "RIGHT", 4, 0)

    local settings = UI.Button(body, "Settings", 66, 22, function() NS.ShowConfig() end)
    settings:SetPoint("TOPRIGHT", 0, 0)
    deleteBtn = UI.Button(body, "Delete", 56, 22, function()
        local set = Resolve()
        if set then
            StaticPopup_Show("GEARLIST_DELETE", set.name, NS.CharName(view.char), { char = view.char, set = set.name })
        end
    end)
    deleteBtn:SetPoint("RIGHT", settings, "LEFT", -4, 0)
    local importBtn = UI.Button(body, "Import", 60, 22, function() NS.ShowImport() end)
    importBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)

    local setDD = UI.Dropdown(body, 170, function()
        local items = {}
        for _, set in ipairs(NS.SetsFor(view.char)) do
            local have, total = NS.Progress(set)
            items[#items + 1] = { value = set.name, label = ("%s  (%d/%d)"):format(set.name, have, total) }
        end
        if #items == 0 then items[1] = { value = false, label = "Nothing imported yet" } end
        return items
    end, function() Resolve(); return view.set or false end, function(v)
        if v then
            view.set = v
            db.active[view.char] = v
        end
    end)
    setDD:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)

    local charDD = UI.Dropdown(body, 160, function()
        local items, shown = {}, false
        for _, key in ipairs(NS.CharList(true)) do
            items[#items + 1] = { value = key, label = NS.CharLabel(key) }
            if key == view.char then shown = true end
        end
        -- The character on screen stays pickable after its last list is deleted.
        if not shown and NS.db.chars[view.char] then
            items[#items + 1] = { value = view.char, label = NS.CharLabel(view.char) }
        end
        return items
    end, function() Resolve(); return view.char end, function(v) view.char, view.set = v, nil end)
    charDD:SetPoint("RIGHT", setDD, "LEFT", -6, 0)

    -- Column names for each view, lined up with the rows (which start 2 px inside the list).
    frame.sortHeaders = {}
    for _, h in ipairs(HEADERS) do
        local right = h[3] and COL[h[3]] or (bodyW - 14)
        local header = Header(body, h[1], h[2], right - COL[h[1]] - 2)
        header:SetPoint("TOPLEFT", COL[h[1]] + 2, -26)
        table.insert(headers.gear, header)
        frame.sortHeaders[h[1]] = header
    end
    frame.filterOptions = function(key) return FilterOptions(key, Resolve(), Own()) end
    frame.setFilter = SetFilter
    for _, h in ipairs(DHEADERS) do
        local label = UI.Text(body, h[2], "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", DCOL[h[1]] + 2, -28)
        table.insert(headers.dungeons, label)
    end

    list = UI.List(body, bodyW, ROW_H, ROWS, Render, RowClick)
    list:SetPoint("TOPLEFT", 0, -(26 + HEAD_H))
    for _, row in ipairs(list.rows) do Decorate(row) end

    dlist = UI.List(body, bodyW, ROW_H, ROWS, RenderDungeon, DungeonClick)
    dlist:SetPoint("TOPLEFT", 0, -(26 + HEAD_H))
    for _, row in ipairs(dlist.rows) do DecorateDungeon(row) end
    dlist:Hide()
    frame.dungeonList = dlist

    -- One message for both views, on a frame above the lists so neither covers it.
    local over = CreateFrame("Frame", nil, body)
    over:SetAllPoints(list)
    over:SetFrameLevel(list:GetFrameLevel() + 20)
    empty = UI.Text(over, "", "GameFontHighlight")
    empty:SetPoint("CENTER")
    empty:SetWidth(bodyW - 120)
    empty:SetJustifyH("CENTER")

    UI.Track({ Refresh = Refresh })
end

function NS.ShowMain(char, set)
    if not (NS.db and NS.playerKey) then return end
    if not frame then Build() end
    if char then view.char, view.set = char, set end
    if frame:IsShown() then UI.RefreshAll() else frame:Show() end
end

function NS.ToggleMain()
    if frame and frame:IsShown() then frame:Hide() else NS.ShowMain() end
end

-- Gear, bags, marks or sets changed.
function NS.OnChanged()
    if frame and frame:IsShown() then UI.RefreshAll() end
end

-- Walking into a dungeon or a new zone changes what's highlighted.
local moved = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    pcall(moved.RegisterEvent, moved, event)
end
moved:SetScript("OnEvent", function()
    if not (frame and frame:IsShown()) then return end
    C_Timer.After(0.5, function()
        if frame:IsShown() then UI.RefreshAll() end
    end)
end)

-- Item names, links and prices arrive late; redraw once they do.
local late = CreateFrame("Frame")
local waiting = false
pcall(late.RegisterEvent, late, "GET_ITEM_INFO_RECEIVED")
late:SetScript("OnEvent", function()
    if waiting or not (frame and frame:IsShown()) then return end
    waiting = true
    C_Timer.After(0.3, function()
        waiting = false
        if frame:IsShown() then Refresh() end
    end)
end)

function GearList_OnCompartmentClick()
    NS.ToggleMain()
end
