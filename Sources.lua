---------------------------------------------------------
--  GearList - where a listed item comes from and what it costs
--  Author: Dranged
---------------------------------------------------------
-- The export names items and nothing else, so this is put together in game:
--   Vendor costs (gold, currencies, token items): the built-in table in
--     Data/Vendors.lua (every currency's price list from Wowhead), and whatever
--     is read off a merchant window when you open one. What the game shows wins,
--     is remembered for the whole account, and covers anything the table lacks.
--   Crafted items and enchants: CraftRoute's recipes (profession, skill,
--     pattern, materials), priced with Auctionator.
--   Dungeon drops and quest rewards: DungeonJournal's loot tables.
--   Every other quest reward, and drops outside those dungeons: Questie's
--     database (which quests give the item, which creatures or objects drop it).
--   Bind on equip: Auctionator's price.
--   Reputation and profession requirements: the item's own tooltip. The game
--     colours a requirement red while you don't meet it.
-- Every source is optional. Without its addon that part just isn't shown.

local ADDON, NS = ...

---------------------------------------------------------
--  SECTION: Small helpers
---------------------------------------------------------
-- Money the way vendors show it: a number and the coin's icon, no letters.
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

local function Gold(g)
    return (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)) .. GOLD
end

-- The two biggest coins that matter: gold alone from 100, else gold and silver,
-- else silver and copper.
local function Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g >= 100 then return Gold(g) end
    if g > 0 then return Gold(g) .. " " .. s .. SILVER end
    if s > 0 then return s .. SILVER .. " " .. c .. COPPER end
    return c .. COPPER
end
NS.Money = Money

-- For a narrow column: whole gold from 10 gold up.
local function ShortMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    if copper < 100000 then return Money(copper) end
    return Gold(math.floor(copper / 10000 + 0.5))
end
NS.ShortMoney = ShortMoney

local function AHPrice(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
    if ok and type(price) == "number" and price > 0 then return price end
end

local function ItemName(id, names)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name or (names and names[id]) or ("item " .. id)
end

-- "(have 12)", green when that's enough.
local function Have(have, need)
    return (" |cff%s(have %d)|r"):format(have >= need and "40ff40" or "ff6060", have)
end

---------------------------------------------------------
--  SECTION: Vendor costs, read at the merchant
---------------------------------------------------------
local function CostHave(c)
    if c.cur and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, c.cur)
        if ok and type(info) == "table" and type(info.quantity) == "number" then return info.quantity end
    end
    if c.id then return NS.Count(c.id, true) end
    return nil
end

-- The currency's or token's icon as inline text, or nil when there's none to show.
local function CostTexture(c)
    local tex = c.tex
    if not tex and c.id and C_Item and C_Item.GetItemIconByID then tex = C_Item.GetItemIconByID(c.id) end
    if not tex and c.cur and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, c.cur)
        tex = ok and type(info) == "table" and info.iconFileID or nil
    end
    if type(tex) == "number" or type(tex) == "string" then return tex end
end

local function CostIcon(c)
    local tex = CostTexture(c)
    return tex and ("|T%s:12:12:0:0|t"):format(tostring(tex)) or nil
end

-- The little icon beside a source says what kind it is, so the text doesn't have to.
local ICON = {
    drop = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",  -- a boss or creature
    chest = "Interface\\Icons\\INV_Box_01",                        -- a chest or other object
    world = "Interface\\Icons\\INV_Misc_Bag_10",                   -- drops from many creatures
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    vendor = "Interface\\GossipFrame\\VendorGossipIcon",
    craft = "Interface\\Icons\\Trade_BlackSmithing",
    auction = "Interface\\MoneyFrame\\UI-GoldIcon",
}
NS.SOURCE_ICON = ICON
local PROFESSION_ICON = {
    Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting = "Interface\\Icons\\Trade_Engraving", Engineering = "Interface\\Icons\\Trade_Engineering",
    Leatherworking = "Interface\\Icons\\Trade_LeatherWorking", Tailoring = "Interface\\Icons\\Trade_Tailoring",
    Cooking = "Interface\\Icons\\INV_Misc_Food_15", Mining = "Interface\\Icons\\Trade_Mining",
}

-- A cost's name: stored for currencies, asked of the game for token items.
local function CostName(c)
    if c.name then return c.name end
    if c.id then return ItemName(c.id) end
    return "?"
end

-- What a currency's vendor is called in the Source column: "Tarnished Real vendor".
local CURRENCY_SHORT = { [3469] = "Tarnished Real", [1792] = "Honor", [515] = "Darkmoon" }

-- The vendor's zone, in the game's own words when it's stored by ID.
local function VendorZone(v)
    if v.zoneID and C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, v.zoneID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return (v.zone and v.zone ~= "") and v.zone or nil
end

local function IsGear(id)
    local fn = C_Item and C_Item.IsEquippableItem
    if not fn then return false end
    local ok, yes = pcall(fn, id)
    return ok and yes and true or false
end

-- Listed items and any other gear on sale here get their price written down.
local function ScanMerchant()
    if not (NS.db and GetMerchantNumItems and GetMerchantItemID) then return end
    local listed, changed = NS.ItemIndex(), false
    for i = 1, GetMerchantNumItems() or 0 do
        local id = GetMerchantItemID(i)
        if id and (listed[id] or IsGear(id)) then
            local gold
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
                gold = ok and type(info) == "table" and info.price or nil
            elseif GetMerchantItemInfo then
                gold = select(3, GetMerchantItemInfo(i))
            end
            local costs = {}
            if GetMerchantItemCostInfo and GetMerchantItemCostItem then
                for k = 1, GetMerchantItemCostInfo(i) or 0 do
                    local tex, value, link, curName = GetMerchantItemCostItem(i, k)
                    if type(value) == "number" and value > 0 then
                        local isLink = type(link) == "string"
                        costs[#costs + 1] = {
                            id = isLink and tonumber(link:match("item:(%d+)")) or nil,
                            cur = isLink and tonumber(link:match("currency:(%d+)")) or nil,
                            name = (isLink and link:match("%[(.-)%]")) or curName or "?",
                            n = value, tex = (type(tex) == "number" or type(tex) == "string") and tex or nil,
                        }
                    end
                end
            end
            NS.db.vendors[id] = {
                npc = UnitName("npc"), zone = GetRealZoneText and GetRealZoneText() or nil,
                gold = (type(gold) == "number" and gold > 0) and gold or nil,
                costs = costs, t = time(),
            }
            if listed[id] then changed = true end
        end
    end
    if changed then NS.Changed() end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "MERCHANT_SHOW")
pcall(ev.RegisterEvent, ev, "MERCHANT_UPDATE")
ev:SetScript("OnEvent", function() pcall(ScanMerchant) end)

---------------------------------------------------------
--  SECTION: CraftRoute recipes
---------------------------------------------------------
-- CraftRoute marks faction-only text as {A:...} / {H:...}; keep your side's.
local function FactionText(text)
    local mine = (UnitFactionGroup("player") == "Horde") and "H" or "A"
    text = text:gsub("{(%a):([^}]*)}", function(f, t) return f == mine and t or "" end)
    text = text:gsub("%s*/%s*/%s*", " / "):gsub("^%s*/%s*", ""):gsub("%s*/%s*$", "")
    return text
end

local function Professions()
    local CR = _G.CraftRoute
    local profs = type(CR) == "table" and CR.professions
    return type(profs) == "table" and profs or nil
end

-- The recipe that makes this item.
local function RecipeForItem(id)
    for profName, p in pairs(Professions() or {}) do
        local spell = type(p.byItem) == "table" and p.byItem[id]
        local r = spell and type(p.recipes) == "table" and p.recipes[spell]
        if type(r) == "table" then return r, profName, p.names end
    end
end

-- The recipe cast as this spell (enchants are their own recipe).
local function RecipeForSpell(spell)
    if not spell then return nil end
    for profName, p in pairs(Professions() or {}) do
        local r = type(p.recipes) == "table" and p.recipes[spell]
        if type(r) == "table" then return r, profName, p.names end
    end
end

-- Adds a recipe to out: one short part, then tooltip lines for the pattern and each material.
local function AddRecipe(out, r, profName, names, own)
    local total, unpriced = 0, 0
    local mats = {}
    for _, m in ipairs(type(r.reagents) == "table" and r.reagents or {}) do
        local id, n = m[1], m[2] or 1
        if type(id) == "number" then
            local price = AHPrice(id)
            if price then total = total + price * n else unpriced = unpriced + 1 end
            mats[#mats + 1] = { id = id, n = n, price = price }
        end
    end
    -- A profession and skill already says "made"; no label in front.
    local head = profName .. (r.learn and (" " .. r.learn) or "")
    local cost
    if #mats > 0 and total > 0 then
        cost = "mats " .. Money(total) .. (unpriced > 0 and "+" or "")
    end
    out.parts[#out.parts + 1] = head
    if out.kinds then out.kinds[#out.parts] = "craft" end
    if #out.parts == 1 then out.icon, out.kind = PROFESSION_ICON[profName] or ICON.craft, "craft" end
    out.tip[#out.tip + 1] = { head, cost }
    out.recipe = { r = r, prof = profName, mats = total > 0 and total or nil, unpriced = unpriced }
    if type(r.pattern) == "string" then
        local from = type(r.src) == "string" and FactionText(r.src) or ""
        if from == "Pattern" or from == "Unknown" then from = "" end
        out.tip[#out.tip + 1] = { "  " .. r.pattern, from ~= "" and from or nil }
    end
    for _, m in ipairs(mats) do
        local left = ("  %d %s"):format(m.n, ItemName(m.id, names))
        if own then left = left .. Have(NS.Count(m.id, true), m.n) end
        out.tip[#out.tip + 1] = { left, m.price and Money(m.price * m.n) or "|cff808080no price|r" }
    end
end

---------------------------------------------------------
--  SECTION: DungeonJournal loot tables
---------------------------------------------------------
local journal -- itemID -> { { kind = "drop" / "quest", who, where }, ... }; false = not installed

local function BuildJournal()
    local FDJ = _G.ForeverDungeonJournal_NS
    local DB = type(FDJ) == "table" and FDJ.DB
    if type(DB) ~= "table" then return false end
    local mine = UnitFactionGroup("player")
    local idx = {}
    -- ord: the boss's place in the dungeon's own order; quests after the bosses.
    local function Add(id, kind, who, where, ord)
        if type(id) ~= "number" then return end
        idx[id] = idx[id] or {}
        table.insert(idx[id], { kind = kind, who = tostring(who or "?"), where = tostring(where), ord = ord })
    end
    for dungeon, d in pairs(DB) do
        if type(d) == "table" then
            for n, boss in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
                for _, loot in ipairs(type(boss) == "table" and type(boss.loot) == "table" and boss.loot or {}) do
                    if type(loot) == "table" then Add(loot[1], "drop", boss.name, dungeon, n) end
                end
            end
            for n, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
                -- A quest for the other faction is no use to you.
                if type(q) == "table" and (q.faction == nil or q.faction == "Both" or q.faction == mine) then
                    for _, reward in ipairs(type(q.rewardItems) == "table" and q.rewardItems or {}) do
                        if type(reward) == "table" then Add(reward[1], "quest", q.name, dungeon, 1000 + n) end
                    end
                end
            end
        end
    end
    return idx
end

local function Journal(id)
    if journal == nil then
        local ok, idx = pcall(BuildJournal)
        journal = ok and idx or false
    end
    return journal and journal[id] or nil
end

---------------------------------------------------------
--  SECTION: Requirements from the item's tooltip
---------------------------------------------------------
local reqCache = {} -- itemID -> { t, list }
local reqPatterns, levelPattern

local function ToPattern(fmt)
    local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%%d?%$?[sd]", "(.+)")
    return "^" .. p .. "$"
end

-- { { text, unmet, kind, a, b }, ... }: reputation and profession lines. nil until the item has loaded.
local function Requirements(id)
    local hit = reqCache[id]
    if hit and (GetTime() - hit.t) < 30 then return hit.list end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    if not reqPatterns then
        reqPatterns = {}
        -- Reputation first: the plain "Requires %s" line would match those too.
        for _, def in ipairs({ { "rep", ITEM_REQ_REPUTATION }, { "skill", ITEM_MIN_SKILL }, { "other", ITEM_REQ_SKILL } }) do
            if type(def[2]) == "string" then
                reqPatterns[#reqPatterns + 1] = { kind = def[1], pattern = ToPattern(def[2]) }
            end
        end
        levelPattern = type(ITEM_MIN_LEVEL) == "string" and ToPattern(ITEM_MIN_LEVEL) or nil
    end
    local ok, list = pcall(function()
        local data = C_TooltipInfo.GetItemByID(id)
        if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines < 2 then return nil end
        local out = {}
        for i = 2, #data.lines do
            local line = data.lines[i]
            local text = type(line) == "table" and line.leftText
            if type(text) == "string" and not (levelPattern and text:match(levelPattern)) then
                for _, p in ipairs(reqPatterns) do
                    local a, b = text:match(p.pattern)
                    if a then
                        local c = line.leftColor
                        local red = type(c) == "table" and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
                        -- rep: a = faction, b = standing. skill: a = profession, b = skill level.
                        out[#out + 1] = { text = text, unmet = red and true or false, kind = p.kind, a = a, b = b }
                        break
                    end
                end
            end
        end
        return out
    end)
    if not ok or not list then return nil end
    reqCache[id] = { t = GetTime(), list = list }
    return list
end

---------------------------------------------------------
--  SECTION: Questie's database
---------------------------------------------------------
-- QuestieDB keeps, for every item, the quests that reward it and the creatures,
-- objects and vendors it comes from. It's read through the globals it sets up
-- (ItemDB, QuestDB, NpcDB, ObjectDB), one field function per column.
local questie = {} -- itemID -> { quests = { { name, text, zone } }, drops = { { text, chest, zone } }, world, vendor, vendorZone }
local MAX_DROPPERS = 5 -- dropped by more creatures than this, it's a world drop

local function QField(db, field, id)
    local d = _G[db]
    local fn = type(d) == "table" and d[field]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, id)
    if ok then return value end
end

local function AreaName(id)
    if type(id) ~= "number" or id <= 0 or not (C_Map and C_Map.GetAreaInfo) then return nil end
    local ok, name = pcall(C_Map.GetAreaInfo, id)
    if ok and type(name) == "string" and name ~= "" then return name end
end

-- "Zone, text", or the text alone when the zone isn't known.
local function Placed(zone, text)
    return zone and (zone .. ", " .. text) or text
end

local function Questie(id)
    if questie[id] then return questie[id] end
    if type(_G.ItemDB) ~= "table" then return nil end -- not loaded (yet): ask again next time
    local q = { quests = {}, drops = {} }
    local mine = UnitFactionGroup("player")
    local masks = type(LibQuestieDB) == "table" and type(LibQuestieDB.Enum) == "table"
        and LibQuestieDB.Enum.factionRaceMasks
    local myMask = type(masks) == "table" and masks[mine] or nil

    local seen = {}
    for _, questID in ipairs(QField("ItemDB", "questRewards", id) or {}) do
        local name = QField("QuestDB", "name", questID)
        -- requiredRaces is a race bitmask, 0 for everyone. A quest for the other faction is no use to you.
        local races = QField("QuestDB", "requiredRaces", questID)
        local other = myMask and bit and type(races) == "number" and races ~= 0 and bit.band(races, myMask) == 0
        if type(name) == "string" and not other and not seen[name] then
            seen[name] = true
            -- zoneOrSort is a zone ID when positive.
            local zone = AreaName(QField("QuestDB", "zoneOrSort", questID))
            q.quests[#q.quests + 1] = { name = name, text = Placed(zone, "Quest: " .. name), zone = zone }
        end
    end

    local npcs = QField("ItemDB", "npcDrops", id) or {}
    local objects = QField("ItemDB", "objectDrops", id) or {}
    if #npcs + #objects > MAX_DROPPERS then
        q.world = true
    else
        local had = {}
        local function Dropper(db, dropID)
            local name = QField(db, "name", dropID)
            if type(name) ~= "string" then return end
            local zone = AreaName(QField(db, "zoneID", dropID))
            local text = Placed(zone, name)
            if not had[text] then
                had[text] = true
                q.drops[#q.drops + 1] = { text = text, chest = (db == "ObjectDB"), zone = zone }
            end
        end
        for _, npcID in ipairs(npcs) do Dropper("NpcDB", npcID) end
        for _, objectID in ipairs(objects) do Dropper("ObjectDB", objectID) end
    end

    -- A vendor on your side. Questie knows who sells it, not for how much.
    local side = (mine == "Horde") and "H" or "A"
    for _, npcID in ipairs(QField("ItemDB", "vendors", id) or {}) do
        local friendly = QField("NpcDB", "friendlyToFaction", npcID)
        local name = QField("NpcDB", "name", npcID)
        if type(name) == "string" and (type(friendly) ~= "string" or friendly:find(side, 1, true)) then
            q.vendorZone = AreaName(QField("NpcDB", "zoneID", npcID))
            q.vendor = Placed(q.vendorZone, name)
            break
        end
    end
    questie[id] = q
    return q
end

---------------------------------------------------------
--  SECTION: Where you are
---------------------------------------------------------
-- The names of where you're standing: the instance's inside a dungeon or raid, and the zone's.
function NS.Here()
    local names = {}
    if IsInInstance and GetInstanceInfo then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") then
            local name = GetInstanceInfo()
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
    end
    local zone = GetRealZoneText and GetRealZoneText()
    if type(zone) == "string" and zone ~= "" and zone ~= names[1] then names[#names + 1] = zone end
    return names
end

local function Norm(name)
    return (name:lower():gsub("^%s*the%s+", ""):gsub("%s+$", ""))
end

-- The game and the journal don't always name a dungeon alike ("Stratholme" and
-- "Stratholme: Living", "Blackrock Spire" and "Lower Blackrock Spire", "The Temple of
-- Atal'Hakkar" and "Sunken Temple"). So a place matches when the names are the same,
-- when the part before a colon is, when one holds the other, or through one of the
-- journal's own search aliases. Every wing of a dungeon matches while you're in it.
local function SamePlace(place, here)
    local a, b = Norm(place), Norm(here)
    if a == b or a:match("^(.-):") == b then return true end
    if #a >= 6 and #b >= 6 and (a:find(b, 1, true) or b:find(a, 1, true)) then return true end
    local FDJ = _G.ForeverDungeonJournal_NS
    local all = type(FDJ) == "table" and FDJ.DUNGEON_SEARCH_ALIASES
    local aliases = type(all) == "table" and all[place]
    for _, alias in ipairs(type(aliases) == "table" and aliases or {}) do
        if type(alias) == "string" and #alias >= 6 and Norm(alias) == b then return true end
    end
    return false
end

-- Is any of these places (a source's, or one dungeon's name) where you are? names = NS.Here().
function NS.IsHere(places, names)
    for _, place in ipairs(places or {}) do
        for _, here in ipairs(names or {}) do
            if SamePlace(place, here) then return true end
        end
    end
    return false
end

---------------------------------------------------------
--  SECTION: Putting it together
---------------------------------------------------------
-- own = the list belongs to the character you're on, so "have" counts and
-- unmet requirements mean something.
-- Returns, for the row: parts (where it comes from) with kinds beside them, icon and kind (the first
-- part's: "drop", "chest", "world", "quest", "vendor", "currency", "craft",
-- "auction"), cost (gold or token amounts) and rep (reputation needed), each
-- short text. For sorting by cost: costSort = { group, name, amount }, group 1
-- currencies, 2 token items, 3 gold. places = every dungeon or zone it can be
-- got in, for NS.IsHere. For the tooltip:
-- tip = { { left, right }, ... }. And the pieces themselves: vendor,
-- recipe ({ r, prof, mats, unpriced }), journal, auction (price), reqs, and
-- plan: "vendor", or the cheaper of "craft" and "auction".
function NS.ItemSource(id, own)
    local out = { parts = {}, kinds = {}, tip = {}, costs = {}, places = {} }
    -- Every part keeps its kind; the first part's icon and kind are the row's.
    local function Part(text, icon, kind)
        out.parts[#out.parts + 1] = text
        out.kinds[#out.parts] = kind
        if #out.parts == 1 then out.icon, out.kind = icon, kind end
    end

    -- What a merchant window showed you beats the built-in table.
    local v = NS.db.vendors[id] or (NS.VENDORS and NS.VENDORS[id])
    if v then
        local zone = VendorZone(v)
        local bits = {}
        for _, c in ipairs(v.costs or {}) do
            local have = own and CostHave(c)
            bits[#bits + 1] = c.n .. " " .. CostName(c) .. (have and Have(have, c.n) or "")
            out.costs[#out.costs + 1] = c
        end
        if v.gold then
            bits[#bits + 1] = Money(v.gold)
            out.gold = v.gold
        end
        local cost = table.concat(bits, " + ")
        -- A currency says which vendor it is, so that's all the row needs: "Tarnished Real
        -- vendor", with the currency's own icon. Others get place then name; the vendor
        -- icon is what tells them from a boss. The tooltip has the seller either way.
        local currency, paidIn
        for _, c in ipairs(v.costs or {}) do
            if c.cur then currency, paidIn = CURRENCY_SHORT[c.cur] or c.name, c break end
        end
        if currency then
            Part(currency .. " vendor", CostTexture(paidIn) or ICON.vendor, "currency")
            out.costSort = { 1, CostName(paidIn), paidIn.n }
        else
            Part(v.npc and ((zone and (zone .. ", ") or "") .. v.npc) or "Vendor", ICON.vendor, "vendor")
            local token = v.costs and v.costs[1]
            if token then
                out.costSort = { 2, CostName(token), token.n }
            elseif v.gold then
                out.costSort = { 3, "", v.gold }
            end
        end
        local who = "Sold by " .. (v.npc or "a vendor")
        if zone then
            who = who .. " (" .. zone .. ")"
            out.places[#out.places + 1] = zone
        end
        out.tip[#out.tip + 1] = { who, cost ~= "" and cost or nil }
        out.vendor = v

        -- The cost column: each amount with its icon, red while you're short of it.
        local short = {}
        for _, c in ipairs(v.costs or {}) do
            local have = own and CostHave(c)
            local n = tostring(c.n)
            if have then n = (have >= c.n and "|cff40ff40" or "|cffff6060") .. n .. "|r" end
            short[#short + 1] = n .. (CostIcon(c) or (" " .. CostName(c)))
        end
        if v.gold then short[#short + 1] = ShortMoney(v.gold) end
        out.cost = table.concat(short, " ")
    end

    local r, profName, names = RecipeForItem(id)
    if r then AddRecipe(out, r, profName, names, own) end

    out.journal = Journal(id)
    for n, j in ipairs(out.journal or {}) do
        -- A drop: the place first, then who, "Stratholme, Ramstein the Gorger". A quest:
        -- its name alone, since the icon says it's a quest. The tooltip spells both out.
        local text = j.where .. ", " .. (j.kind == "quest" and "Quest: " or "") .. j.who
        out.places[#out.places + 1] = j.where
        if n == 1 then
            if j.kind == "quest" then Part(j.who, ICON.quest, "quest") else Part(text, ICON.drop, "drop") end
        end
        out.tip[#out.tip + 1] = { text }
    end

    -- Questie fills in what the journal doesn't have: quests outside its dungeons,
    -- drops it doesn't list, and who sells an item whose price isn't known yet.
    local q = Questie(id)
    if q then
        local inJournal, journalDrop = {}, false
        for _, j in ipairs(out.journal or {}) do
            if j.kind == "quest" then inJournal[j.who] = true else journalDrop = true end
        end
        local first = true
        for _, quest in ipairs(q.quests) do
            if not inJournal[quest.name] then
                if first then Part(quest.name, ICON.quest, "quest") end
                first = false
                out.tip[#out.tip + 1] = { quest.text }
                out.places[#out.places + 1] = quest.zone
            end
        end
        if not journalDrop then
            if q.world then
                Part("World drop", ICON.world, "world")
                out.tip[#out.tip + 1] = { "World drop" }
            end
            for n, drop in ipairs(q.drops) do
                if n == 1 then Part(drop.text, drop.chest and ICON.chest or ICON.drop, drop.chest and "chest" or "drop") end
                out.tip[#out.tip + 1] = { drop.text }
                out.places[#out.places + 1] = drop.zone
            end
        end
        if not v and q.vendor then
            Part(q.vendor, ICON.vendor, "vendor")
            out.tip[#out.tip + 1] = { "Sold by " .. q.vendor }
            out.places[#out.places + 1] = q.vendorZone
        end
    end

    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local bind = select(14, GetInfo(id))
    if bind == 2 then
        local price = AHPrice(id)
        Part("BoE", ICON.auction, "auction")
        out.tip[#out.tip + 1] = { "Binds when equipped", price and ("Auction " .. Money(price)) or "|cff808080no auction price|r" }
        out.auction = price
    end

    -- How you'd pay for it: the vendor if one sells it, else the cheaper of making and buying.
    if out.vendor then
        out.plan = "vendor"
    elseif out.recipe and (not out.auction or (out.recipe.mats and out.recipe.mats <= out.auction)) then
        out.plan = "craft"
        if out.recipe.mats then
            out.cost = "mats " .. ShortMoney(out.recipe.mats) .. (out.recipe.unpriced > 0 and "+" or "")
            out.costSort = { 3, "", out.recipe.mats }
        end
    elseif out.auction then
        out.plan = "auction"
        out.cost = "AH " .. ShortMoney(out.auction)
        out.costSort = { 3, "", out.auction }
    end

    out.reqs = Requirements(id)
    local reps = {}
    for _, q in ipairs(out.reqs or {}) do
        local color = own and (q.unmet and "|cffff6060" or "|cff40ff40") or nil
        local text = color and (color .. q.text .. "|r") or q.text
        out.tip[#out.tip + 1] = { text }
        if q.kind == "rep" then
            -- The rep column: faction and standing, without "Requires".
            local short = q.a .. " - " .. q.b
            reps[#reps + 1] = color and (color .. short .. "|r") or short
        else
            Part(text, nil)
        end
    end
    if #reps > 0 then out.rep = table.concat(reps, ", ") end
    return out
end

-- The same for an entry's enchant: the recipe that casts it, when CraftRoute has it.
function NS.EnchSource(e, own)
    if not e.ench then return nil end
    local r, profName, names = RecipeForSpell(e.ench.spell)
    if not r then return nil end
    local out = { parts = {}, tip = {}, costs = {} }
    AddRecipe(out, r, profName, names, own)
    return out
end

---------------------------------------------------------
--  SECTION: The list's missing items, by dungeon
---------------------------------------------------------
-- Rows for the Dungeons view: the dungeon with the most wanted items first,
-- and under each its bosses in the dungeon's own order (quests after them)
-- with the item each one gives.
--   { dungeon = name, count = wanted items there }
--   { who = boss or "Quest: name", first = first row for that boss, e = the list entry }
-- Also returns how many missing items have no dungeon source. nil when
-- DungeonJournal isn't loaded.
function NS.DungeonRows(set)
    Journal(0)
    if not journal then return nil end
    local byName, dungeons, others, seq = {}, {}, 0, 0
    for _, e in ipairs(set.items) do
        if not NS.ItemDone(e) then
            local drops = journal[e.id]
            if not drops then others = others + 1 end
            for _, j in ipairs(drops or {}) do
                local d = byName[j.where]
                if not d then
                    d = { name = j.where, entries = {}, seen = {}, count = 0 }
                    byName[j.where] = d
                    dungeons[#dungeons + 1] = d
                end
                -- An item two bosses drop is still one item wanted from this dungeon.
                if not d.seen[e] then
                    d.seen[e] = true
                    d.count = d.count + 1
                end
                seq = seq + 1
                d.entries[#d.entries + 1] = {
                    who = (j.kind == "quest" and "Quest: " or "") .. j.who, ord = j.ord or 0, seq = seq, e = e,
                }
            end
        end
    end
    table.sort(dungeons, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local rows = {}
    for _, d in ipairs(dungeons) do
        rows[#rows + 1] = { dungeon = d.name, count = d.count }
        table.sort(d.entries, function(a, b)
            if a.ord ~= b.ord then return a.ord < b.ord end
            if a.who ~= b.who then return a.who < b.who end
            return a.seq < b.seq
        end)
        local last
        for _, x in ipairs(d.entries) do
            rows[#rows + 1] = { who = x.who, first = x.who ~= last, e = x.e }
            last = x.who
        end
    end
    return rows, others
end
