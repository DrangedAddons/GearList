-- Runs GearList against the mock. Globals in: ADDON_DIR, HERE, MOCK, LOOK
dofile(MOCK)

FAILS = 0
local function Check(cond, what)
    if cond then Say("  ok   " .. what) else FAILS = FAILS + 1; Say("  FAIL " .. what) end
end
Say("== look: " .. LOOK)

---------------------------------------------------------
-- The parts of the game GearList reads
---------------------------------------------------------
time, date = os.time, os.date
function GetTime() return 100 end
PLAYER_NAME = "Testdruñ"
function UnitFullName() return PLAYER_NAME, "TestRealm" end
function UnitClass() return "Druid", "DRUID" end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 60 end
function GetRealmName() return "TestRealm" end
function GetRealZoneText() return "Booty Bay" end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid", MAGE = "Mage" }
ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee" } }
ITEM_REQ_REPUTATION = "Requires %s - %s"
ITEM_MIN_SKILL = "Requires %s (%d)"
ITEM_REQ_SKILL = "Requires %s"
ITEM_MIN_LEVEL = "Requires Level %d"
YES, NO, OKAY, CANCEL = "Yes", "No", "Okay", "Cancel"
GameFontHighlightSmall = NewObj("Font")
StaticPopupDialogs = {}
function StaticPopup_Show(which, _, _, data) POPUP = { which = which, data = data } end

local NAMES = {
    [252561] = "Living Crown", [22272] = "Forest's Embrace", [18470] = "Royal Seal of Eldre'Thalas",
    [252551] = "Mender's Leather Gauntlets", [16058] = "Fordring's Seal", [8170] = "Rugged Leather",
    [12803] = "Living Essence", [16204] = "Illusion Dust", [18723] = "Animated Chain Necklace",
}
local BOE = { [252561] = true }
local function Link(id, ench)
    return ("|cffa335ee|Hitem:%d:%s:0:0:0|h[%s]|h|r"):format(id, ench or "", NAMES[id] or ("Item " .. id))
end
local function IdOf(link) return link and tonumber(link:match("item:(%d+)")) end

EQUIPPED, BAGS, BANK = {}, { [0] = {} }, {}
function GetInventoryItemID(_, slot) return IdOf(EQUIPPED[slot]) end
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] end
C_Container = {
    GetContainerNumSlots = function(bag) return BAGS[bag] and 16 or 0 end,
    GetContainerItemLink = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
C_Item = {
    GetItemCount = function(id, bank)
        local n = 0
        for _, link in pairs(EQUIPPED) do if IdOf(link) == id then n = n + 1 end end
        for _, bag in pairs(BAGS) do
            for _, link in pairs(bag) do if IdOf(link) == id then n = n + 1 end end
        end
        return n + (bank and (BANK[id] or 0) or 0)
    end,
    GetItemInfo = function(id)
        local n = NAMES[id]
        if not n then return nil end
        return n, Link(id), 4, 60, 60, "Armor", "Leather", 1, "INVTYPE_HEAD", 1, 0, 4, 2, BOE[id] and 2 or 1
    end,
    GetItemIconByID = function() return 12345 end,
    GetItemNameByID = function(id) return NAMES[id] end,
    RequestLoadItemDataByID = function() end,
    IsEquippableItem = function() return true end,
}
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) TIP_HOOK = fn end }
C_TooltipInfo = {
    GetItemByID = function(id)
        if id ~= 272413 then return { lines = { { leftText = "x" }, { leftText = "Requires Level 60" } } } end
        return { lines = {
            { leftText = "Drape of Recovery" },
            { leftText = "Requires Level 60", leftColor = { r = 1, g = 1, b = 1 } },
            { leftText = "Requires Argent Dawn - Revered", leftColor = { r = 1, g = 0.1, b = 0.1 } },
        } }
    end,
}
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id)
    return ({ [8170] = 5000, [12803] = 20000, [252561] = 3800000, [16204] = 9000 })[id]
end } } }
CraftRoute = { professions = {
    Leatherworking = { names = {}, byItem = { [252561] = 1255016 }, recipes = { [1255016] = {
        name = "Living Crown", item = 252561, learn = 300, src = "Sold by {A:Elf Vendor (Darnassus)} / {H:Orc Vendor (Orgrimmar)}",
        pattern = "Pattern: Living Crown", reagents = { { 8170, 20 }, { 12803, 20 }, { 99999, 1 } },
    } } },
    Enchanting = { names = {}, byItem = {}, recipes = { [23802] = { name = "Enchant Bracer - Healing Power", learn = 300, reagents = { { 16204, 2 } } } } },
} }
ForeverDungeonJournal_NS = { DB = { Scholomance = {
    bosses = { { name = "Darkmaster Gandling", loot = { { 18386, "Padre's Trousers", "Legs", 3 } } } },
}, Stratholme = {
    bosses = {
        { name = "Baroness Anastari", loot = { { 13360, "Gift of the Elven Magi", "Main Hand", 3 } } },
        { name = "Ramstein the Gorger", loot = { { 18723, "Animated Chain Necklace", "Neck", 3 } } },
    },
    quests = {
        { name = "Horde Only", faction = "Horde", rewardItems = { { 13954, "Verdant Footpads", 3 } } },
        { name = "For Everyone", faction = "Both", rewardItems = { { 13178, "Rosewine Circle", 3 } } },
    },
} } }
-- Questie's database: field functions on global tables.
bit = { band = function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end }
LibQuestieDB = { Enum = { factionRaceMasks = { Alliance = 77, Horde = 178 } } }
local MANY = {}
for i = 1, 40 do MANY[i] = 5000 + i end
local QITEMS = {
    [16058] = { questRewards = { 5944 } },                      -- a quest outside any dungeon
    [15805] = { questRewards = { 9001, 9002 } },                -- one quest per faction
    [13178] = { questRewards = { 9003 } },                      -- the journal has this quest already
    [18525] = { npcDrops = { 11486 } },                         -- a boss the journal mock doesn't list
    [18723] = { npcDrops = { 10439 } },                         -- the journal has this drop already
    [13954] = { npcDrops = MANY },                              -- dropped by everything
    [18470] = { objectDrops = { 179501 }, questRewards = { 7507 } },
    [272439] = { vendors = { 227853 } },
    [18386] = { vendors = { 3000, 3001 } },                     -- sold, price not known
}
ItemDB = setmetatable({}, { __index = function(_, field)
    return function(id) return QITEMS[id] and QITEMS[id][field] or nil end
end })
local QUESTS = {
    [5944] = { "In Dreams", 0, 28 }, [9001] = { "For the Horde", 178, 0 }, [9002] = { "Penelope's Errand", 77, -22 },
    [9003] = { "For Everyone", 0, 2017 }, [7507] = { "Nostro's Compendium", 0, 2557 },
}
QuestDB = {
    name = function(id) return QUESTS[id] and QUESTS[id][1] end,
    requiredRaces = function(id) return QUESTS[id] and QUESTS[id][2] end,
    zoneOrSort = function(id) return QUESTS[id] and QUESTS[id][3] end,
}
local NPCS = {
    [11486] = { "Prince Tortheldrin", 2557 }, [10439] = { "Ramstein the Gorger", 2017 },
    [3000] = { "Horde Seller", 1637, "H" }, [3001] = { "Alliance Seller", 1519, "A" }, [227853] = { "Pix Xizzix", 33, "AH" },
}
NpcDB = {
    name = function(id) return NPCS[id] and NPCS[id][1] end,
    zoneID = function(id) return NPCS[id] and NPCS[id][2] end,
    friendlyToFaction = function(id) return NPCS[id] and NPCS[id][3] end,
}
ObjectDB = { name = function(id) return id == 179501 and "Knot Thimblejack's Cache" or nil end, zoneID = function() return 2557 end }
local AREAS = { [28] = "Western Plaguelands", [2557] = "Dire Maul", [2017] = "Stratholme", [1519] = "Stormwind City", [1637] = "Orgrimmar" }

function GetMerchantNumItems() return 1 end
function GetMerchantItemID() return 272439 end
C_MerchantFrame = { GetItemInfo = function() return { price = 150000 } end }
function GetMerchantItemCostInfo() return 1 end
function GetMerchantItemCostItem() return 1, 25, "|cffffffff|Hitem:226404::::|h[Tarnished Undermine Real]|h|r", nil end

local function ReadFile(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end
local SAMPLE = ReadFile(HERE .. "/sample.json")

---------------------------------------------------------
-- Load
---------------------------------------------------------
local NS = LoadAddon(ADDON_DIR, "GearList", {
    "Theme.lua", "Widgets.lua", "Window.lua", "Json.lua", "Core.lua", "Data/Vendors.lua", "Sources.lua", "UI.lua", "Import.lua", "Config.lua",
})

-- JSON reader
local J = NS.Json
local v = J.Decode('{"a":[1,2.5,-3e2,true,false,null],"b":"q\\"\\u00f1\\n","c":{}}')
Check(v.a[1] == 1 and v.a[2] == 2.5 and v.a[3] == -300 and v.a[4] == true and v.a[5] == false and v.a[6] == false, "json: numbers, booleans, null")
Check(v.b == 'q"\195\177\n' and type(v.c) == "table", "json: escapes and \\u codes")
Check(not pcall(J.Decode, '{"a":[1,2'), "json: cut-off text is refused")
Check(not pcall(J.Decode, '{"a":1} extra'), "json: trailing text is refused")
Check(not pcall(J.Decode, "hello"), "json: plain words are refused")

-- Money: numbers with coin icons, no g/s/c letters
local function Plain(text) return (text:gsub("|T.-|t", "#")) end
Check(Plain(NS.Money(1234567)) == "123#" and Plain(NS.Money(63095)) == "6# 30#" and Plain(NS.Money(4550)) == "45# 50#" and Plain(NS.Money(7)) == "7#",
    "money: two biggest coins, as icons")
Check(Plain(NS.ShortMoney(250000)) == "25#" and Plain(NS.ShortMoney(63095)) == "6# 30#" and NS.Money(10000):find("UI-GoldIcon", 1, true)
    and not NS.Money(1234567):find("%d[gsc]"), "money: whole gold from 10 up in the cost column, no letters")

-- Reading the export
local set, err = NS.ParseExport(SAMPLE)
Check(set and #set.items == 17, "export: 17 items" .. (err and (" (" .. err .. ")") or ""))
Check(set.name == "resto" and set.phase == 1 and set.class == "DRUID" and set.forName == "testdruñ", "export: name, phase, class, character")
Check(set.items[1].slot == "HEAD" and set.items[4].slot == "BACK" and set.items[17].slot == "RANGED", "export: sorted into sheet order")
local nEnch, nMark = 0, 0
for _, e in ipairs(set.items) do
    if e.ench then nEnch = nEnch + 1 end
    if e.mark then nMark = nMark + 1 end
end
Check(nEnch == 10 and nMark == 3, "export: 10 enchants, 3 ticked on the site")
Check(select(2, NS.ParseExport("{}")) ~= nil and NS.ParseExport('{"items":[]}') == nil, "export: junk gives a reason, not a set")
Check(NS.ParseExport((SAMPLE:gsub("%s+", " "))) ~= nil, "export: one-line text reads the same")

-- A set typed in for a character before its first login is adopted at login.
GearListDB = {
    chars = { ["testdruñ-TestRealm"] = { name = "testdruñ", realm = "TestRealm", typed = true } },
    sets = { ["testdruñ-TestRealm"] = { set } },
}
set.imported = 1
EQUIPPED[5] = Link(22272, 8492)   -- chest, with the listed armor kit
EQUIPPED[13] = Link(18470)        -- listed as Trinket 2, worn as Trinket 1
BAGS[0][3] = Link(252551)         -- gloves in a bag, no enchant
BANK[16058] = 1                   -- ring in the bank
FireEvent("ADDON_LOADED", "GearList")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD")
FlushTimers()
local db = GearListDB
local KEY = "Testdruñ-TestRealm"
Check(db.sets[KEY] and db.sets[KEY][1] == set and not db.sets["testdruñ-TestRealm"] and not db.chars["testdruñ-TestRealm"],
    "login: the typed-in name's list moved to the real character")
Check(db.chars[KEY] and db.chars[KEY].class == "DRUID" and not db.chars[KEY].typed, "login: character recorded")

local function Entry(id)
    for _, e in ipairs(NS.FindSet(KEY, "resto").items) do if e.id == id then return e end end
end
Check(Entry(22272).st == "equipped" and Entry(22272).est == true, "check: chest worn with the right enchant")
Check(Entry(18470).st == "equipped", "check: trinket counts in the other trinket slot")
Check(Entry(252551).st == "bags" and Entry(252551).est == false, "check: gloves in bags, enchant missing")
Check(Entry(16058).st == "bank" and Entry(16058).est == nil, "check: ring in the bank")
Check(Entry(252561).st == nil and not NS.ItemDone(Entry(252561)), "check: helm missing")
local have, total, eHave, eTotal = NS.Progress(NS.FindSet(KEY, "resto"))
Check(have == 4 and total == 17 and eHave == 1 and eTotal == 10, ("check: progress 4/17 and 1/10 (got %d/%d %d/%d)"):format(have, total, eHave, eTotal))

-- New gear and a new enchant get a chat line.
PRINTED = {}
BAGS[0][4] = Link(252561)
FireEvent("BAG_UPDATE_DELAYED")
FlushTimers()
Check(Entry(252561).st == "bags" and #PRINTED == 1 and PRINTED[1]:find("Living Crown", 1, true), "announce: helm picked up")
BAGS[0][3] = nil
EQUIPPED[10] = Link(252551, 2617)
FireEvent("PLAYER_EQUIPMENT_CHANGED", 10)
FlushTimers()
Check(Entry(252551).st == "equipped" and Entry(252551).est == true and #PRINTED == 2 and PRINTED[2]:find("Enchant Gloves", 1, true),
    "announce: gloves enchanted")
BAGS[0][4] = nil
FireEvent("BAG_UPDATE_DELAYED")
FlushTimers()

-- Sources
FireEvent("MERCHANT_SHOW")
local vend = db.vendors[272439]
Check(vend and vend.gold == 150000 and vend.costs[1].id == 226404 and vend.costs[1].n == 25 and vend.npc == "Tester",
    "sources: vendor price read at the merchant")
local src = NS.ItemSource(272439, true)
Check(src.parts[1] == "Booty Bay, Tester" and src.icon == NS.SOURCE_ICON.vendor and src.cost:find("ff606025|r|T1:", 1, true) and src.cost:find(NS.ShortMoney(150000), 1, true),
    "sources: vendor in the source text, token and gold in the cost (" .. src.cost .. ")")
src = NS.ItemSource(252561, true)
local all = table.concat(src.parts, " | ")
Check(all == "Leatherworking 300 | BoE" and src.plan == "craft" and src.cost:find("^mats ") and src.cost:find(NS.ShortMoney(500000), 1, true),
    "sources: crafted and BoE, cost is the cheaper route (" .. src.cost .. ")")
local tip = {}
for _, l in ipairs(src.tip) do tip[#tip + 1] = l[1] .. " = " .. tostring(l[2]) end
tip = table.concat(tip, "\n")
Check(tip:find("Elf Vendor", 1, true) and not tip:find("Orc Vendor", 1, true), "sources: pattern seller for your faction only")
Check(tip:find("20 Rugged Leather", 1, true) and tip:find("no price", 1, true), "sources: materials listed, unpriced one marked")
src = NS.ItemSource(18723, true)
Check(src.parts[1] == "Stratholme, Ramstein the Gorger" and src.icon == NS.SOURCE_ICON.drop, "sources: dungeon drop, dungeon first, skull icon")
src = NS.ItemSource(13178, true)
Check(src.parts[1] == "For Everyone" and src.icon == NS.SOURCE_ICON.quest and src.tip[1][1] == "Stratholme, Quest: For Everyone"
    and not table.concat(NS.ItemSource(13954, true).parts, " | "):find("Horde Only", 1, true), "sources: quest reward, other faction's left out")
src = NS.ItemSource(272413, true)
Check(src.rep == "|cffff6060Argent Dawn - Revered|r", "sources: unmet reputation in red, in its own text")
-- The built-in table: nobody has opened this vendor.
src = NS.ItemSource(272429, true)
Check(src.parts[1] == "Tarnished Real vendor" and src.icon == NS.SOURCE_ICON.vendor and src.tip[1][1] == "Sold by Pix Xizzix (Stranglethorn Vale)" and src.cost == "50 Tarnished Undermine Real" and src.plan == "vendor",
    "sources: built-in price for an item no merchant window has shown (" .. tostring(src.cost) .. ")")
C_Map = { GetAreaInfo = function(id) return id == 33 and "Schlingendorntal" or nil end }
Check(NS.ItemSource(12252, true).parts[1] == "Schlingendorntal, Zarena Cromwind", "sources: the game names the zone when it can")
C_Map = nil
src = NS.ItemSource(278469, true)
Check(src.parts[1] == "Honor vendor" and src.cost == "10500 Honor Points |cffff606010|r|T12345:12:12:0:0|t",
    "sources: honor and marks, the mark as a count and its icon (" .. tostring(src.cost) .. ")")
Check(NS.ItemSource(272439, true).parts[1] == "Booty Bay, Tester", "sources: what the merchant window showed beats the built-in table")
src = NS.ItemSource(226780, true)
Check(src.parts[1] == "Vendor" and src.cost == NS.ShortMoney(250000) and src.plan == "vendor", "sources: built-in gold price, seller not named (" .. tostring(src.cost) .. ")")
src = NS.ItemSource(12252, true)
Check(src.parts[1] == "Zarena Cromwind" and src.cost == NS.ShortMoney(63095), "sources: built-in gold price with its seller (" .. tostring(src.cost) .. ")")
local nBuilt = 0
for _ in pairs(NS.VENDORS) do nBuilt = nBuilt + 1 end
Check(nBuilt > 2000, "sources: built-in table has " .. nBuilt .. " items")
local es = NS.EnchSource(Entry(18525), true)
Check(es and es.parts[1]:find("^Enchanting 300"), "sources: enchant materials from its recipe")

-- Questie: quests and drops the journal doesn't have
C_Map = { GetAreaInfo = function(id) return AREAS[id] end }
src = NS.ItemSource(16058, true)
Check(src.parts[1] == "In Dreams" and src.icon == NS.SOURCE_ICON.quest and src.tip[1][1] == "Western Plaguelands, Quest: In Dreams",
    "questie: quest reward outside a dungeon, name in the row, zone in the tooltip")
src = NS.ItemSource(15805, true)
Check(#src.parts == 1 and src.parts[1] == "Penelope's Errand", "questie: your faction's quest only (" .. table.concat(src.parts, " | ") .. ")")
src = NS.ItemSource(13178, true)
Check(#src.parts == 1 and src.parts[1] == "For Everyone", "questie: a quest the journal already has isn't listed twice")
Check(NS.ItemSource(18525, true).parts[1] == "Dire Maul, Prince Tortheldrin", "questie: drop from a boss the journal doesn't list")
src = NS.ItemSource(18723, true)
Check(#src.parts == 1 and src.parts[1] == "Stratholme, Ramstein the Gorger", "questie: a drop the journal already has isn't listed twice")
Check(NS.ItemSource(13954, true).parts[1] == "World drop" and NS.ItemSource(13954, true).icon == NS.SOURCE_ICON.world, "questie: dropped by 40 creatures is a world drop")
src = NS.ItemSource(18470, true)
Check(src.parts[1] == "Nostro's Compendium" and src.parts[2] == "Dire Maul, Knot Thimblejack's Cache", "questie: quest and object drop")
src = NS.ItemSource(18386, true)
Check(src.parts[2] == "Stormwind City, Alliance Seller" and src.cost == nil, "questie: your side's vendor when no price is known")
Check(#NS.ItemSource(272439, true).parts == 1, "questie: no second vendor line when the price is known")
C_Map = nil

-- Tooltip note
local lines = {}
GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. ": " .. r end
TIP_HOOK(GameTooltip, { id = 18723 })
Check(#lines == 1 and lines[1] == "Gear list: resto, Neck", "tooltip: listed item gets a line")
TIP_HOOK(GameTooltip, { id = 1 })
Check(#lines == 1, "tooltip: other items get nothing")
db.tooltip = false
TIP_HOOK(GameTooltip, { id = 18723 })
Check(#lines == 1, "tooltip: off when unticked")
db.tooltip = true

---------------------------------------------------------
-- Windows
---------------------------------------------------------
local function ListOf(frame)
    for _, c in ipairs(frame.body._children) do if c.rows then return c end end
end
Check(SLASH_GEARLIST3 == "/gl", "slash: /gl is registered")
SlashCmdList.GEARLIST("")
Check(GearListFrame and GearListFrame:IsShown(), "window: /gearlist opens it")
local list = ListOf(GearListFrame)
Check(list and #list.data == 17, "window: 17 rows of data")
local row = list.rows[1]
Check(row.item and row.item.slot == "HEAD" and row.text:GetText():find("Living Crown", 1, true)
    and row.slot:GetText() == "Head" and row.info:GetText():find("^Leatherworking 300"),
    "window: first row is the helm with its source")
Check(row.ench:GetText() == "Arcanum of Focus" and row.enchHit:IsShown(), "window: enchant column")
Check(list.rows[6].item.slot == "WRISTS" and list.rows[6].ench:GetText() == "Bracer - Healing Power", "window: enchant names lose their first word")
Check(row.cost:GetText():find("^mats ") and row.rep:GetText() == "", "window: cost column")
Check(list.rows[4].item.slot == "BACK" and list.rows[4].rep:GetText():find("Argent Dawn - Revered", 1, true) and list.rows[4].info:GetText():find("^Tarnished Real vendor")
    and list.rows[4].cost:GetText():find("^75"), "window: reputation column, built-in vendor price")
Check(list.rows[5].cost:GetText() == "" and list.rows[5].rep:GetText() == "" and not list.rows[5].sicon:IsShown(), "window: finished rows have no cost, rep or source icon")
Check(row.sicon:IsShown() and list.rows[2].sicon:IsShown(), "window: source icon on rows still to get")
Check(list.rows[5].have:IsShown() and list.rows[5].ehave:IsShown() and not row.have:IsShown() and not row.ehave:IsShown(),
    "window: rows you have are tinted, missing ones aren't")
Check(list.rows[5].info:GetText() == "Equipped" and list.rows[2].info:GetText():find("^Stratholme, Ramstein the Gorger"), "window: where it is, or how to get it")
row:GetScript("OnEnter")(row)
row.enchHit:GetScript("OnEnter")(row.enchHit)

-- Hand ticks
row:Click("RightButton")
Check(Entry(252561).mark == true and row.info:GetText() == "Ticked", "window: right-click ticks by hand")
Check(row.have:IsShown() and not row.ehave:IsShown(), "window: item half tinted, enchant half waits for the enchant")
row:Click("RightButton")
Check(Entry(252561).mark == nil and row.info:GetText():find("Leatherworking", 1, true), "window: right-click again unticks")
row.enchHit:Click("RightButton")
Check(Entry(252561).emark == true, "window: enchant ticks on its own")
row.enchHit:Click("RightButton")

-- Sorting by clicking a column's name
local H = GearListFrame.sortHeaders
H.name:Click()
Check(db.sortKey == "name" and not db.sortDesc and list.rows[1].item.name == "Animated Chain Necklace", "sort: by item name")
H.name:Click()
Check(db.sortDesc and list.rows[1].item.name == "Verdant Footpads", "sort: the same header again reverses it")
H.src:Click()
Check(db.sortKey == "src" and not db.sortDesc and NS.ItemSource(list.rows[1].item.id, true).kind == "drop"
    and NS.ItemDone(list.data[#list.data]), "sort: by source kind, drops first, rows you have last")
H.src:Click()
Check(NS.ItemDone(list.data[#list.data]) and not NS.ItemDone(list.rows[1].item), "sort: rows you have stay last when reversed")
H.cost:Click()
Check(list.rows[1].item.id == 272413 and list.rows[2].item.id == 272429, "sort: by cost, currencies first and the dearest on top")
H.rep:Click()
Check(list.rows[1].item.id == 272413, "sort: by reputation, rows that need one first")
H.ench:Click()
Check(list.rows[1].item.ench and list.rows[1].item.ench.name == "Arcanum of Focus" and list.data[#list.data].ench == nil, "sort: by enchant, slots without one last")
H.info:Click()
Check(db.sortKey == "info", "sort: by details")
H.slot:Click()
Check(db.sortKey == "slot" and not db.sortDesc and list.rows[1].item.slot == "HEAD" and list.rows[17].item.slot == "RANGED", "sort: Slot puts the sheet order back")
H.slot:Click()
Check(not db.sortDesc and list.rows[1].item.slot == "HEAD", "sort: Slot never reverses")

-- Filters from a right-click on a column's name
local F, opts = GearListFrame, nil
local function Has(items, value)
    for _, it in ipairs(items) do if it.value == value then return it end end
end
H.src:Click("RightButton") -- opens the menu
opts = F.filterOptions("src")
Check(opts[1].value == false and Has(opts, "drop") and Has(opts, "quest") and Has(opts, "currency") and Has(opts, "craft")
    and not Has(opts, "@clear"), "filter: source menu offers the kinds this list has")
F.setFilter("src", "quest")
local allQuest = #list.data > 0
for _, e in ipairs(list.data) do if NS.ItemSource(e.id, true).kind ~= "quest" then allQuest = false end end
Check(allQuest and H.src.mark:IsShown() and not H.name.mark:IsShown(), "filter: only quest rows left (" .. #list.data .. "), header marked")
Check(Has(F.filterOptions("cost"), "@clear"), "filter: other menus offer Clear every filter")
F.setFilter("ench", "todo")
local n2 = #list.data
local both = true
for _, e in ipairs(list.data) do if not e.ench or NS.EnchDone(e) then both = false end end
Check(both and n2 <= 4, "filter: columns combine (" .. n2 .. " quest rows with an enchant to do)")
F.setFilter("src", "@clear")
Check(#list.data == 17 and not H.src.mark:IsShown() and not H.ench.mark:IsShown(), "filter: Clear every filter restores the list")
F.setFilter("info", "Stratholme")
Check(#list.data == 2 and Has(F.filterOptions("info"), "Scholomance") and not Has(F.filterOptions("info"), "For Everyone"),
    "filter: details by place (" .. #list.data .. " from Stratholme), quest names aren't places")
F.setFilter("info", false)
F.setFilter("cost", "Tarnished Undermine Real")
-- Two from the built-in table and the one the mock merchant sold for the same token.
Check(#list.data == 3 and Has(F.filterOptions("cost"), "gold") and Has(F.filterOptions("cost"), "any"), "filter: cost by currency (" .. #list.data .. " rows)")
F.setFilter("cost", false)
F.setFilter("rep", "Argent Dawn")
Check(#list.data == 1 and list.rows[1].item.id == 272413, "filter: reputation by faction")
F.setFilter("rep", false)
F.setFilter("name", "have")
Check(#list.data == 4, "filter: items you have (" .. #list.data .. ")")
F.setFilter("name", false)
F.setFilter("slot", "jewel")
Check(#list.data == 5, "filter: neck, rings and trinkets (" .. #list.data .. ")")
F.setFilter("src", "auction")
Check(#list.data == 0, "filter: nothing matching shows the note, not an error")
F.setFilter("slot", "@clear")
Check(#list.data == 17, "filter: all clear again")

-- Where you are: rows you can get here are washed blue
local IN, ZONE = nil, "Booty Bay"
function IsInInstance() return IN ~= nil, IN and "party" or "none" end
function GetInstanceInfo() return IN end
function GetRealZoneText() return ZONE end
local function HereRows()
    local n, ids = 0, {}
    for _, r in ipairs(list.rows) do
        if r.item and r:IsShown() and r.here:IsShown() then n = n + 1; ids[r.item.id] = true end
    end
    return n, ids
end
NS.Changed()
local nHere, hereIds = HereRows()
Check(nHere == 1 and hereIds[272439] and GearListFrame.nsTitle:GetText() == "Gear List: 1 item to get in Booty Bay",
    "here: the vendor in your zone (" .. nHere .. " row, title says so)")
IN, ZONE = "Stratholme", "Stratholme"
FireEvent("ZONE_CHANGED_NEW_AREA")
FlushTimers()
nHere, hereIds = HereRows()
Check(nHere == 3 and hereIds[13360] and hereIds[18723] and hereIds[13178] and list.rows[2].hereBar:IsShown()
    and GearListFrame.nsTitle:GetText() == "Gear List: 3 items to get in Stratholme", "here: inside a dungeon, its drops and quest reward (" .. nHere .. " rows)")
Check(not list.rows[5].here:IsShown(), "here: a row you already have isn't highlighted")
ForeverDungeonJournal_NS.DUNGEON_SEARCH_ALIASES = { ["Sunken Temple"] = { "st", "sunken", "temple of atal'hakkar" } }
Check(NS.IsHere({ "Stratholme: Living" }, { "Stratholme" }) and NS.IsHere({ "Dire Maul: East" }, { "Dire Maul" })
    and NS.IsHere({ "Lower Blackrock Spire" }, { "Blackrock Spire" }) and NS.IsHere({ "The Deadmines" }, { "Deadmines" })
    and NS.IsHere({ "Sunken Temple" }, { "The Temple of Atal'Hakkar" }), "here: the journal's dungeon names match the game's")
Check(not NS.IsHere({ "Scholomance" }, { "Stratholme" }) and not NS.IsHere({ "Blackrock Depths" }, { "Blackrock Spire" })
    and not NS.IsHere({ "Sunken Temple" }, { "st" }), "here: other dungeons don't")
db.tab = "dungeons"
NS.Changed()
local dh = GearListFrame.dungeonList
Check(dh.rows[1].text:GetText():find("Stratholme", 1, true) and dh.rows[1].text:GetText():find("you are here", 1, true)
    and dh.rows[2].band:IsShown() and dh.rows[4].band:IsShown(), "here: Dungeons tab marks the dungeon you're in and its rows")
Check(dh.rows[5].text:GetText():find("Scholomance", 1, true) and not dh.rows[5].text:GetText():find("you are here", 1, true)
    and not dh.rows[6].band:IsShown() and not dh.rows[7].band:IsShown(), "here: other dungeons and the note stay plain")
db.tab = "gear"
IN, ZONE = nil, "Elwynn Forest"
FireEvent("ZONE_CHANGED_NEW_AREA")
FlushTimers()
Check(HereRows() == 0 and GearListFrame.nsTitle:GetText() == "Gear List", "here: nothing highlighted where nothing drops")

-- Dungeons view
local rows, others = NS.DungeonRows(NS.FindSet(KEY, "resto"))
Check(rows[1].dungeon == "Stratholme" and rows[1].count == 3 and rows[5].dungeon == "Scholomance" and rows[5].count == 1,
    "dungeons: the one with the most wanted items comes first")
Check(rows[2].who == "Baroness Anastari" and rows[2].first and rows[2].e.id == 13360 and rows[3].who == "Ramstein the Gorger"
    and rows[4].who == "Quest: For Everyone" and rows[6].who == "Darkmaster Gandling", "dungeons: bosses in dungeon order, quests after")
Check(others == 9, "dungeons: " .. tostring(others) .. " missing items have no dungeon source")
db.tab = "dungeons"
NS.Changed()
local dl = GearListFrame.dungeonList
Check(dl:IsShown() and not list:IsShown() and #dl.data == 7, "dungeons: tab swaps the whole view (" .. #dl.data .. " rows)")
Check(dl.rows[1].text:GetText():find("Stratholme", 1, true) and dl.rows[1].count:GetText() == "3 items"
    and dl.rows[2].boss:GetText() == "Baroness Anastari" and dl.rows[2].slot:GetText() == "Main hand", "dungeons: header and boss rows")
Check(dl.rows[7].text:GetText():find("9 more missing items", 1, true), "dungeons: note for the rest")
dl.rows[2]:GetScript("OnEnter")(dl.rows[2])
dl.rows[1]:Click()
db.tab = "gear"
NS.Changed()
Check(list:IsShown() and not dl:IsShown() and #list.data == 17, "dungeons: back to the gear view")

db.showDone = false
NS.Changed()
Check(#list.data == 13, "window: the 4 finished slots hidden (" .. #list.data .. " left)")
db.showDone = true
NS.Changed()

-- Import window: paste, preview, replace
SlashCmdList.GEARLIST("import")
Check(GearListImport and GearListImport:IsShown(), "import: opens")
local edit
local function FindEdit(f)
    for _, c in ipairs(f._children) do
        if c._type == "EditBox" and c._scripts.OnTextChanged then edit = c end
        FindEdit(c)
    end
end
FindEdit(GearListImport)
Check(edit ~= nil, "import: paste box found")
Entry(13178).mark = true -- a hand tick that should survive the replace
edit:SetText(SAMPLE)
edit:GetScript("OnTextChanged")(edit)
GearListImport:GetScript("OnUpdate")(GearListImport, 1)
local importBtn, preview
for _, c in ipairs(GearListImport.body._children) do
    if c._type == "Button" and (c:GetText() == "Replace" or c:GetText() == "Import") then importBtn = c end
end
for _, r in ipairs(GearListImport.body._regions) do
    if r._type == "FontString" and tostring(r:GetText()):find("17 items", 1, true) then preview = r end
end
Check(preview and preview:GetText():find("10 enchants", 1, true) and preview:GetText():find("already has a list", 1, true), "import: preview describes the set")
Check(importBtn and importBtn:GetText() == "Replace", "import: button says Replace for a same-named list")
PRINTED = {}
importBtn:Click()
Check(#db.sets[KEY] == 1 and db.sets[KEY][1] ~= set and PRINTED[1] and PRINTED[1]:find("Replaced", 1, true), "import: replaced in place")
Check(Entry(13178).mark == true and Entry(22272).st == "equipped", "import: hand tick kept, gear checked again")
Check(not GearListImport:IsShown() and GearListFrame:IsShown(), "import: closes and shows the list")

-- A list for a character that hasn't been logged in
local alt = NS.AddTypedChar("Altmage")
local altSet = NS.ParseExport(SAMPLE)
NS.SaveSet(alt, altSet, "healing")
Check(alt == "Altmage-TestRealm" and db.sets[alt][1].name == "healing" and db.sets[alt][1].items[1].st == nil, "alt: list filed under the typed name, unchecked")
NS.ShowMain(alt, "healing")
Check(#list.data == 17 and list.rows[5].info:GetText() ~= "Equipped", "alt: its list shows without your gear")
Check(GearListFrame.nsTitle:GetText():find("Altmage, not checked", 1, true), "alt: title says it hasn't been checked")
lines = {}
TIP_HOOK(GameTooltip, { id = 18723 })
Check(#lines == 2 and lines[2] == "Gear list: Altmage: healing, Neck", "tooltip: alt's list named")
NS.DeleteSet(alt, "healing")
Check(not db.sets[alt] and not db.chars[alt], "alt: deleting its last list forgets the typed name")
Check(#list.data == 17 and list.rows[1].item == Entry(252561), "window: falls back to your own list")

-- Settings
SlashCmdList.GEARLIST("config")
Check(GearListConfig and GearListConfig:IsShown(), "settings: opens")
GearList_OnCompartmentClick()
Check(not GearListFrame:IsShown(), "compartment click toggles the list")

Say(FAILS == 0 and "  all passed" or ("  " .. FAILS .. " failed"))
