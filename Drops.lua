---------------------------------------------------------
--  GearList - banner, sound and chat line when a listed item drops
--  Author: Dranged
---------------------------------------------------------
-- The game says an item has dropped in three places: the loot window
-- (LOOT_READY / LOOT_OPENED), a roll starting (START_LOOT_ROLL) and the
-- "receives loot" chat line when someone picks it up (CHAT_MSG_LOOT). An item
-- counts when it's on one of this character's lists and isn't found or ticked.

local ADDON, NS = ...
local UI = NS.UI

local HOLD, FADE = 7, 1 -- seconds a banner row stays, then how long it fades
local REPEAT = 20       -- the loot window and the roll popup report one drop moments apart
local MAX_ROWS = 4
local ROW_H, ICON, PAD = 56, 44, 6

-- Tried in order until the client plays one; not every kit is in every client.
local SOUNDS = { "UI_EPICLOOT_TOAST", "LFG_REWARDS", "IG_QUEST_LIST_COMPLETE", "RAID_WARNING" }

local WHAT = { roll = "Roll started", loot = "Dropped", test = "Test" }
local SAY = {
    roll = "%s is up for a roll. It's on your list: %s.",
    loot = "%s dropped. It's on your list: %s.",
    test = "%s would be announced like this. It's on your list: %s.",
}

-- Loot text can be withheld from addons in combat; such a value can't be read.
local function Plain(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

local function ItemID(link)
    link = Plain(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- This character's lists that still want the item: "Restoration, Head; kitty, Head".
local function WantedBy(id)
    local refs = id and NS.playerKey and NS.ItemIndex()[id]
    if not refs then return nil end
    local parts = {}
    for _, ref in ipairs(refs) do
        if ref.key == NS.playerKey and not NS.ItemDone(ref.e) then
            parts[#parts + 1] = ref.set.name .. ", " .. NS.SlotLabel(ref.e.slot)
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

---------------------------------------------------------
--  SECTION: Banner
---------------------------------------------------------
-- Rows stack downward from a point above the middle of the screen, clear of
-- the unit frames below it. Clicks pass through.
local anchor
local pool, active = {}, {}

local function Layout()
    for i, r in ipairs(active) do
        r:ClearAllPoints()
        r:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (ROW_H + 4))
    end
end

local function Retire(r)
    for i, a in ipairs(active) do
        if a == r then table.remove(active, i) break end
    end
    r:Hide()
    pool[#pool + 1] = r
    Layout()
end

local function Tick(r, elapsed)
    r.age = r.age + elapsed
    if r.age >= HOLD + FADE then
        Retire(r)
    elseif r.age > HOLD then
        r:SetAlpha(1 - (r.age - HOLD) / FADE)
    end
end

local function NewRow()
    local r = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    r:SetHeight(ROW_H)
    r:EnableMouse(false)
    UI.Backdrop(r, 0.06, 0.06, 0.07, 0.92, 0.4, 0.8, 1, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", PAD, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = UI.Text(r, "", _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -2)
    r.note = UI.Text(r, "", "GameFontHighlight")
    r.note:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 2)
    r:SetScript("OnUpdate", Tick)
    return r
end

-- The item's name in its quality colour, without the link's brackets.
local function Coloured(link, id)
    local colour, name
    if type(link) == "string" then colour, name = link:match("(|c%x%x%x%x%x%x%x%x)|Hitem.-|h%[(.-)%]|h") end
    if name then return colour .. name .. "|r" end
    local GetName = C_Item and C_Item.GetItemNameByID
    return "|cffffffff" .. ((GetName and GetName(id)) or ("Item " .. id)) .. "|r"
end

local function ShowBanner(id, link, what, lists)
    if not anchor then
        anchor = CreateFrame("Frame", "GearListDropBanner", UIParent)
        anchor:SetSize(1, 1)
        anchor:SetPoint("TOP", UIParent, "CENTER", 0, 200)
        anchor:SetFrameStrata("HIGH")
    end
    if #active >= MAX_ROWS then Retire(active[1]) end
    local r = table.remove(pool) or NewRow()
    local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    r.icon:SetTexture((GetIcon and GetIcon(id)) or 134400) -- 134400: the question mark
    r.name:SetText(Coloured(link, id))
    r.note:SetText(("|cff66ccff%s|r  on your list: %s"):format(WHAT[what], lists))
    pcall(NS.NoteThemeFonts, r)
    r:SetWidth(math.max(360, ICON + PAD * 2 + 20 + math.max(r.name:GetStringWidth(), r.note:GetStringWidth())))
    r.age, r.item = 0, id
    r:SetAlpha(1)
    r:Show()
    active[#active + 1] = r
    Layout()
    return r
end

local function PlayAlert()
    if not SOUNDKIT then return end
    for _, key in ipairs(SOUNDS) do
        local kit = SOUNDKIT[key]
        if kit then
            local ok, played = pcall(PlaySound, kit, "Master")
            if ok and played then return end
        end
    end
end

---------------------------------------------------------
--  SECTION: Alerts
---------------------------------------------------------
local lastAlert = {} -- itemID -> GetTime() of its last alert
local lastSaid = {}  -- itemID -> GetTime() of its last loot-window chat line
local seen = {}      -- "corpse GUID:itemID" or "roll:N" -> true, for this session

-- One drop, one alert: `source` names the corpse or roll so reopening a corpse
-- stays quiet, and the same item inside REPEAT seconds is the same drop seen
-- twice (the loot window and the roll popup, or LOOT_READY and LOOT_OPENED).
local function Alert(id, link, what, source)
    local db = NS.db
    if not db or not id then return end
    local lists = WantedBy(id)
    if not lists then return end
    if source then
        if seen[source] then return end
        seen[source] = true
    end
    local now = GetTime()
    if lastAlert[id] and now - lastAlert[id] < REPEAT then return end
    lastAlert[id] = now

    if db.dropBanner then ShowBanner(id, link, what, lists) end
    if db.dropSound then PlayAlert() end
    if db.dropChat then
        if what == "loot" then lastSaid[id] = now end
        NS.Print(SAY[what]:format(Plain(link) or Coloured(nil, id), lists))
    end
    return true
end

-- True just after the loot-window chat line for this item, so picking it up
-- doesn't get a second line from the bag check a second later.
function NS.DropJustSaid(id)
    local t = lastSaid[id]
    return t ~= nil and GetTime() - t < 5
end

local function OnLootWindow()
    if not (GetNumLootItems and GetLootSlotLink) then return end
    for slot = 1, (GetNumLootItems() or 0) do
        local ok, link = pcall(GetLootSlotLink, slot)
        local id = ok and ItemID(link)
        if id then
            local source
            if GetLootSourceInfo then
                local okS, guid = pcall(GetLootSourceInfo, slot)
                guid = okS and Plain(guid)
                if type(guid) == "string" then source = guid .. ":" .. id end
            end
            Alert(id, link, "loot", source)
        end
    end
end

local function OnRoll(rollID)
    if not (rollID and GetLootRollItemLink) then return end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    local id = ok and ItemID(link)
    if id then Alert(id, link, "roll", "roll:" .. tostring(rollID)) end
end

-- "%s receives loot: %s." as a Lua pattern, so only the pick-up lines count:
-- roll choices and roll results come through CHAT_MSG_LOOT with a link too.
-- `first` is which capture holds the player's name (the order moves in some languages).
local function Compile(fmt)
    if type(fmt) ~= "string" then return nil end
    local out, order, i = { "^" }, {}, 1
    while i <= #fmt do
        local a, b, pos, kind = fmt:find("^%%(%d*)%$?([sd])", i)
        if a then
            order[#order + 1] = tonumber(pos) or (#order + 1)
            out[#out + 1] = (kind == "d") and "(%d+)" or "(.-)"
            i = b + 1
        else
            local c = fmt:sub(i, i)
            out[#out + 1] = c:match("%w") and c or ("%" .. c)
            i = i + 1
        end
    end
    out[#out + 1] = "$"
    local first = 1
    for n, pos in ipairs(order) do
        if pos == 1 then first = n end
    end
    return { pat = table.concat(out), first = first }
end

local others
local function Looter(text)
    if not others then
        others = {}
        for _, key in ipairs({ "LOOT_ITEM_MULTIPLE", "LOOT_ITEM", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_PUSHED" }) do
            others[#others + 1] = Compile(_G[key])
        end
    end
    for _, p in ipairs(others) do
        local caps = { text:match(p.pat) }
        if caps[p.first] then return caps[p.first] end
    end
end

local function OnLootChat(text)
    local db = NS.db
    if not (db and db.dropChat) then return end
    text = Plain(text)
    if type(text) ~= "string" then return end
    local id = ItemID(text)
    local lists = id and WantedBy(id)
    if not lists then return end
    local who = Looter(text)
    if not who or who == "" then return end -- your own pick-up; the bag check says that one
    who = who:match("^[^-]+") or who
    if who == UnitName("player") then return end
    local link = text:match("(|c%x+|Hitem.-|h.-|h|r)") or Coloured(nil, id)
    NS.Print(("%s got %s, which is on your list: %s."):format(who, link, lists))
end

-- A banner for the first missing item on this character's lists, for trying
-- the look and the sound without waiting for a drop.
function NS.TestDrop()
    local db = NS.db
    local sets = db and NS.playerKey and db.sets[NS.playerKey]
    local pick
    for _, set in ipairs(sets or {}) do
        for _, e in ipairs(set.items) do
            if not NS.ItemDone(e) then pick = e break end
        end
        if pick then break end
    end
    if not pick then
        NS.Print("Nothing to show: no list on this character has a missing item.")
        return
    end
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = GetInfo(pick.id)
    lastAlert[pick.id] = nil
    return Alert(pick.id, link, "test")
end

local ev = CreateFrame("Frame")
for _, name in ipairs({ "LOOT_READY", "LOOT_OPENED", "START_LOOT_ROLL", "CHAT_MSG_LOOT" }) do
    pcall(ev.RegisterEvent, ev, name) -- an event this client doesn't have is skipped
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if not (NS.db and NS.playerKey) then return end
    -- A read the game refuses mid-fight must not throw an error at the player.
    -- The last one is kept in NS.dropError for the tests and for debugging.
    local ok, err
    if event == "START_LOOT_ROLL" then
        ok, err = pcall(OnRoll, arg1)
    elseif event == "CHAT_MSG_LOOT" then
        ok, err = pcall(OnLootChat, arg1)
    else
        ok, err = pcall(OnLootWindow)
    end
    if not ok then NS.dropError = err end
end)
