---------------------------------------------------------
--  GearList - gear sets from sixtyupgrades.com as an in-game checklist
--  Author: Dranged
---------------------------------------------------------
-- You paste a set's Export text, pick the character it's for, and get a list of
-- every slot's item and enchant, ticked off from what that character wears and
-- carries.
--
-- Sets are kept account-wide, filed under "Name-Realm", so a set can be pasted
-- on one character and applied to another. A character's own gear can only be
-- read while you're on it, so each entry keeps the answer from the last check
-- (st / est) and other characters' lists show that.

local ADDON, NS = ...

local DEFAULTS = {
    theme = "auto",
    minimap = { hide = false },
    tooltip = true,   -- item tooltips say when the item is on a list
    announce = true,  -- chat line when a listed item or enchant turns up
    showDone = true,  -- finished slots stay in the list
    tab = "gear",     -- the list window's view: "gear" or "dungeons"
    sortKey = "slot", -- the gear list's sort column; "slot" is the character-sheet order
    sortDesc = false,
    chars = {},       -- "Name-Realm" -> { name, realm, class, faction, level, seen, typed, specs }
    sets = {},        -- "Name-Realm" -> { set, ... }
    active = {},      -- "Name-Realm" -> name of the set last looked at
    vendors = {},     -- itemID -> { npc, zone, gold, costs } read at a merchant (Sources.lua)
}

local db

function NS.Print(msg)
    print("|cff66ccffGearList|r " .. msg)
end

---------------------------------------------------------
--  SECTION: Slots
---------------------------------------------------------
-- The export's slot names, in character-sheet order, with the game's slot number.
local SLOTS = {
    { "HEAD", 1, "Head" }, { "NECK", 2, "Neck" }, { "SHOULDERS", 3, "Shoulders" },
    { "BACK", 15, "Back" }, { "CHEST", 5, "Chest" }, { "SHIRT", 4, "Shirt" },
    { "TABARD", 19, "Tabard" }, { "WRISTS", 9, "Wrists" }, { "HANDS", 10, "Hands" },
    { "WAIST", 6, "Waist" }, { "LEGS", 7, "Legs" }, { "FEET", 8, "Feet" },
    { "FINGER_1", 11, "Ring 1" }, { "FINGER_2", 12, "Ring 2" },
    { "TRINKET_1", 13, "Trinket 1" }, { "TRINKET_2", 14, "Trinket 2" },
    { "MAIN_HAND", 16, "Main hand" }, { "OFF_HAND", 17, "Off hand" },
    { "RANGED", 18, "Ranged/Relic" }, { "AMMO", 0, "Ammo" },
}
local ALIAS = {
    SHOULDER = "SHOULDERS", WRIST = "WRISTS", HAND = "HANDS", CLOAK = "BACK",
    FINGER1 = "FINGER_1", FINGER2 = "FINGER_2", TRINKET1 = "TRINKET_1", TRINKET2 = "TRINKET_2",
    MAINHAND = "MAIN_HAND", OFFHAND = "OFF_HAND", TWO_HAND = "MAIN_HAND", TWOHAND = "MAIN_HAND",
    RELIC = "RANGED",
}
-- Either slot of a pair counts: a ring listed as Ring 1 is fine worn as Ring 2.
local PARTNER = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }

local SLOT_ID, SLOT_LABEL, SLOT_ORDER = {}, {}, {}
for i, s in ipairs(SLOTS) do
    SLOT_ID[s[1]], SLOT_LABEL[s[1]], SLOT_ORDER[s[1]] = s[2], s[3], i
end

local function SlotKey(raw)
    local key = tostring(raw or ""):upper():gsub("[%s%-]+", "_")
    return ALIAS[key] or key
end

function NS.SlotLabel(key)
    if SLOT_LABEL[key] then return SLOT_LABEL[key] end
    -- A slot this addon doesn't know: show the export's word for it.
    local text = key:gsub("_", " "):lower()
    return (text:gsub("^%l", string.upper))
end

---------------------------------------------------------
--  SECTION: Characters
---------------------------------------------------------
function NS.SameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if a == b then return true end
    if strcmputf8i then
        local ok, r = pcall(strcmputf8i, a, b)
        if ok then return r == 0 end
    end
    return a:lower() == b:lower()
end

-- The known character with this name, the one on your realm first.
function NS.FindChar(name)
    if type(name) ~= "string" or name == "" then return nil end
    local found
    for key, c in pairs(db.chars) do
        if NS.SameName(c.name, name) then
            if c.realm == NS.playerRealm then return key end
            found = found or key
        end
    end
    return found
end

-- A character the addon hasn't been logged in on yet, by name, on your realm.
-- Its sets move to the real record the first time you log in on it.
function NS.AddTypedChar(name)
    name = tostring(name or ""):gsub("|", ""):gsub("%s+", "")
    if name == "" then return nil end
    for key, c in pairs(db.chars) do
        if c.realm == NS.playerRealm and NS.SameName(c.name, name) then return key end
    end
    local key = name .. "-" .. NS.playerRealm
    db.chars[key] = { name = name, realm = NS.playerRealm, typed = true }
    return key
end

-- Known characters: yours first, then by name. withSets = only ones that have a list.
function NS.CharList(withSets)
    local keys = {}
    for key in pairs(db.chars) do
        if not withSets or key == NS.playerKey or #(db.sets[key] or {}) > 0 then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        if (a == NS.playerKey) ~= (b == NS.playerKey) then return a == NS.playerKey end
        return a:lower() < b:lower()
    end)
    return keys
end

function NS.CharName(key)
    local c = db.chars[key]
    return c and c.name or tostring(key)
end

function NS.CharLabel(key)
    local c = db.chars[key]
    if not c then return tostring(key) end
    local text = c.name
    local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    if color then
        text = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, c.name)
    end
    if c.realm ~= NS.playerRealm then text = text .. " - " .. c.realm end
    if c.typed then text = text .. " |cff808080(not logged in yet)|r" end
    return text
end

function NS.ClassName(token)
    if type(token) ~= "string" or token == "" then return nil end
    local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
    if loc then return loc end
    return (token:lower():gsub("^%l", string.upper))
end

local function RegisterPlayer()
    local name, realm = UnitFullName("player")
    name = name or UnitName("player")
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    end
    local key = name .. "-" .. realm
    NS.playerKey, NS.playerName, NS.playerRealm = key, name, realm

    -- A name typed in before this character was ever logged in: take over its sets.
    if not db.chars[key] then
        for k, c in pairs(db.chars) do
            if c.typed and c.realm == realm and NS.SameName(c.name, name) then
                db.sets[key], db.sets[k] = db.sets[k], nil
                db.active[key], db.active[k] = db.active[k], nil
                db.chars[k] = nil
                break
            end
        end
    end
    local _, class = UnitClass("player")
    local was = db.chars[key]
    db.chars[key] = {
        name = name, realm = realm, class = class,
        faction = UnitFactionGroup("player"), level = UnitLevel("player"), seen = time(),
        specs = was and was.specs or nil, -- read again once the talents are in (ReadSpecs)
    }
end

---------------------------------------------------------
--  SECTION: Reading an export
---------------------------------------------------------
local function Clean(text, max)
    text = tostring(text or ""):gsub("|", ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if max and #text > max then text = text:sub(1, max) end
    return text
end

-- text: what Export on sixtyupgrades.com gives. Returns a set, or nil and why not.
function NS.ParseExport(text)
    if type(text) ~= "string" or not text:find("%S") then return nil, "Nothing pasted yet." end
    if #text > 400000 then return nil, "That's far too long to be one gear set." end
    local ok, data = pcall(NS.Json.Decode, text)
    if not ok then
        return nil, "That isn't a complete export (" .. tostring(data) .. "). Copy all of the text and paste again."
    end
    if type(data) ~= "table" or type(data.items) ~= "table" then
        return nil, "No item list in that text. Use Export on your set at sixtyupgrades.com and copy all of it."
    end

    local who = type(data.character) == "table" and data.character or {}
    local set = {
        name = Clean(data.name, 40),
        phase = tonumber(data.phase),
        class = type(who.gameClass) == "string" and who.gameClass:upper() or nil,
        forName = type(who.name) == "string" and Clean(who.name, 40) or nil,
        level = tonumber(who.level),
        items = {},
    }
    if set.name == "" then set.name = "Gear list" end
    if set.forName == "" then set.forName = nil end
    -- What the site calls the set's stat weights ("Restoration EP"): a hint at the spec it's for.
    local points = type(data.points) == "table" and data.points[1]
    if type(points) == "table" and type(points.name) == "string" then
        set.pointsName = Clean(points.name, 40)
        if set.pointsName == "" then set.pointsName = nil end
    end

    for n, it in ipairs(data.items) do
        local id = type(it) == "table" and tonumber(it.id)
        if id then
            local e = {
                slot = SlotKey(it.slot), id = id, n = n,
                name = Clean(it.name, 80),
                mark = (it.acquired == true) or nil, -- ticked as acquired on the site
            }
            if e.name == "" then e.name = "Item " .. id end
            local en = it.enchant
            if type(en) == "table" and (tonumber(en.id) or tonumber(en.spellId)) then
                e.ench = { id = tonumber(en.id), spell = tonumber(en.spellId), name = Clean(en.name, 80) }
                if e.ench.name == "" then e.ench.name = "Enchant" end
            end
            set.items[#set.items + 1] = e
        end
    end
    if #set.items == 0 then return nil, "That export has no items in it." end
    table.sort(set.items, function(a, b)
        local oa, ob = SLOT_ORDER[a.slot] or 99, SLOT_ORDER[b.slot] or 99
        if oa ~= ob then return oa < ob end
        return a.n < b.n
    end)
    for _, e in ipairs(set.items) do e.n = nil end
    return set
end

---------------------------------------------------------
--  SECTION: Sets
---------------------------------------------------------
local index -- itemID -> { { key, set, e }, ... } for tooltips; rebuilt when sets change

function NS.Changed()
    if NS.OnChanged then NS.OnChanged() end
end

function NS.SetsFor(key)
    return (key and db.sets[key]) or {}
end

function NS.FindSet(key, name)
    if not name then return nil end
    for i, set in ipairs(NS.SetsFor(key)) do
        if NS.SameName(set.name, name) then return set, i end
    end
end

function NS.ItemDone(e) return (e.st ~= nil) or (e.mark == true) end
function NS.EnchDone(e) return (e.est == true) or (e.emark == true) end

-- items had, items listed, enchants done, enchants listed
function NS.Progress(set)
    local have, total, eHave, eTotal = 0, 0, 0, 0
    for _, e in ipairs(set.items) do
        total = total + 1
        if NS.ItemDone(e) then have = have + 1 end
        if e.ench then
            eTotal = eTotal + 1
            if NS.EnchDone(e) then eHave = eHave + 1 end
        end
    end
    return have, total, eHave, eTotal
end

-- Files set under the character. A set of the same name is replaced, keeping
-- hand ticks on slots whose item (or enchant) didn't change. Returns the set
-- and whether it replaced one.
function NS.SaveSet(key, set, name)
    set.name = Clean(name, 40)
    if set.name == "" then set.name = "Gear list" end
    set.imported = time()
    db.sets[key] = db.sets[key] or {}
    local old, at = NS.FindSet(key, set.name)
    if old then
        local was = {}
        for _, e in ipairs(old.items) do was[e.slot .. ":" .. e.id] = e end
        for _, e in ipairs(set.items) do
            local o = was[e.slot .. ":" .. e.id]
            if o then
                e.mark = e.mark or o.mark
                if e.ench and o.ench and e.ench.id == o.ench.id then e.emark = o.emark end
            end
        end
        set.spec = old.spec -- still the list for the spec it was tied to
        db.sets[key][at] = set
    else
        table.insert(db.sets[key], set)
    end
    db.active[key] = set.name
    index = nil
    if key == NS.playerKey then NS.ScanNow() end
    NS.Changed()
    return set, old ~= nil
end

function NS.DeleteSet(key, name)
    local _, at = NS.FindSet(key, name)
    if not at then return end
    table.remove(db.sets[key], at)
    if db.active[key] and NS.SameName(db.active[key], name) then db.active[key] = nil end
    if #db.sets[key] == 0 then
        db.sets[key] = nil
        -- A typed-in name with nothing left under it has no reason to stay.
        if db.chars[key] and db.chars[key].typed then db.chars[key] = nil end
    end
    index = nil
    NS.Changed()
end

---------------------------------------------------------
--  SECTION: Dual spec
---------------------------------------------------------
-- The game keeps two talent builds, spec groups 1 and 2. A list can be tied to
-- one of them (set.spec), and a group has one list at most. The list tied to
-- the group you're in is the one that opens. A character's groups can only be
-- read while you're on it, so what was read is kept in its record:
--   specs = { n = how many groups, active = the one it's in, names = { [group] = talent tree } }

-- The talent tree with the most points in a group's build, which is what
-- players call the spec. false with no points spent, nil while the game has
-- no build to read.
local function ReadSpecName(group)
    local configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group)
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    -- The class's three trees are trait groups of the one tree.
    local trees = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if type(trees) ~= "table" or #trees == 0 then return nil end
    table.sort(trees, function(a, b) return a.orderIndex < b.orderIndex end)
    local ids = {}
    for i, t in ipairs(trees) do ids[i] = t.groupID end
    local spent = {}
    for _, g in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local c = g.currencyInfos and g.currencyInfos[1]
        if c then spent[g.traitNodeGroupID] = c.spent end
    end
    local name, best = false, 0
    for _, t in ipairs(trees) do
        local n = spent[t.groupID] or 0
        if n > best and type(t.displayName) == "string" and t.displayName ~= "" then name, best = t.displayName, n end
    end
    return name
end

-- Reads this character's spec groups into its record. Returns the group it's in.
local function ReadSpecs()
    local c = db.chars[NS.playerKey]
    if not c then return 1 end
    local okN, n = pcall(GetNumSpecGroups)
    n = (okN and type(n) == "number" and n >= 2) and 2 or 1
    local okA, active = pcall(function() return C_SpecializationInfo.GetActiveSpecGroup() end)
    active = (okA and active == 2 and n == 2) and 2 or 1
    local was = c.specs and c.specs.names or {}
    local names = {}
    for g = 1, n do
        local ok, name = pcall(ReadSpecName, g)
        if ok and name ~= nil then
            names[g] = name or nil
        else
            names[g] = was[g] -- not readable right now: keep what it was called
        end
    end
    c.specs = { n = n, active = active, names = names }
    return active
end

-- How many spec groups the character had when last seen (1 until then).
function NS.SpecCount(key)
    local c = db.chars[key]
    return c and c.specs and c.specs.n or 1
end

function NS.ActiveSpec(key)
    local c = db.chars[key]
    return c and c.specs and c.specs.active or 1
end

function NS.SpecName(key, group)
    local c = db.chars[key]
    local name = c and c.specs and c.specs.names and c.specs.names[group]
    return name or ("Spec " .. group)
end

-- The list tied to a spec group, if any.
function NS.SpecSet(key, group)
    for _, set in ipairs(NS.SetsFor(key)) do
        if set.spec == group then return set end
    end
end

-- Ties the named list to the group (no name: the group has no list). A list
-- tied to the other group moves over.
function NS.SetSpec(key, group, name)
    for _, set in ipairs(NS.SetsFor(key)) do
        if set.spec == group then set.spec = nil end
    end
    local set = name and NS.FindSet(key, name)
    if set then set.spec = group end
    NS.Changed()
end

local function Words(text)
    local out = {}
    for w in tostring(text or ""):lower():gmatch("%a+") do
        if #w >= 3 then out[#out + 1] = w end
    end
    return out
end

-- Which of the character's groups a list looks made for: its name and the
-- name of its stat weights ("resto", "Restoration EP") against each group's
-- talent tree, a word of one starting a word of the other. nil when neither
-- group fits or both do.
function NS.GuessSpec(key, set)
    local c = db.chars[key]
    local specs = c and c.specs
    if not specs or specs.n ~= 2 then return nil end
    local said = Words((set.name or "") .. " " .. (set.pointsName or ""))
    local hit
    for g = 1, 2 do
        local fits = false
        for _, t in ipairs(Words(specs.names[g])) do
            for _, w in ipairs(said) do
                if t:sub(1, #w) == w or w:sub(1, #t) == t then fits = true end
            end
        end
        if fits then
            if hit then return nil end
            hit = g
        end
    end
    return hit
end

-- Reads the groups again and, when the one you're in changed (or this is the
-- first read of the session), makes its list the one on show.
local specSeen
local function FollowSpec()
    if not NS.playerKey then return end
    local active = ReadSpecs()
    if active ~= specSeen then
        specSeen = active
        local set = NS.SpecSet(NS.playerKey, active)
        if set then
            db.active[NS.playerKey] = set.name
            if NS.OnSpecList then NS.OnSpecList(set.name) end
        end
    end
    NS.Changed()
end

local specQueued = false
local function QueueSpecs()
    if specQueued then return end
    specQueued = true
    C_Timer.After(0.3, function()
        specQueued = false
        FollowSpec()
    end)
end

---------------------------------------------------------
--  SECTION: Checking your gear
---------------------------------------------------------
local function LinkIDs(link)
    if type(link) ~= "string" then return nil end
    local id, ench = link:match("item:(%d+):(%d*)")
    if not id then id = link:match("item:(%d+)") end
    return tonumber(id), tonumber(ench) or 0
end

local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local function Count(id, bank)
    local ok, n = pcall(ItemCount, id, bank)
    return (ok and type(n) == "number") and n or 0
end
NS.Count = Count

-- What you wear and carry right now. An enchant is nil / false when the game
-- hasn't given the item's link yet.
local function Snapshot()
    local snap = { eq = {}, bag = {} }
    for slot = 0, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            local lid, ench = LinkIDs(GetInventoryItemLink("player", slot))
            snap.eq[slot] = { id = id, ench = (lid == id) and ench or nil }
        end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local id, ench = LinkIDs(C_Container.GetContainerItemLink(bag, slot))
                if not id and C_Container.GetContainerItemID then
                    id, ench = C_Container.GetContainerItemID(bag, slot), false
                end
                if id then
                    local copies = snap.bag[id] or {}
                    snap.bag[id] = copies
                    copies[#copies + 1] = ench
                end
            end
        end
    end
    return snap
end

local function LinkOrName(e)
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = GetInfo(e.id)
    return link or ("|cffffffff" .. e.name .. "|r")
end

-- Works out where each of set's items is and whether its enchant is on.
-- Each real copy of an item answers for one list entry only, so two of the
-- same ring need two rings. Returns true when anything changed.
local function CheckSet(set, snap, announce)
    local items = set.items
    local res, usedEq = {}, {}
    local function Claim(i, slot)
        local eq = snap.eq[slot]
        if eq and eq.id == items[i].id and not usedEq[slot] then
            usedEq[slot] = true
            res[i] = { st = "equipped", ench = eq.ench }
            return true
        end
    end
    -- Worn in the listed slot, then in its pair (or anywhere, for a slot this addon doesn't know).
    for i, e in ipairs(items) do
        local slot = SLOT_ID[e.slot]
        if slot then Claim(i, slot) end
    end
    for i, e in ipairs(items) do
        if not res[i] then
            local slot = SLOT_ID[e.slot]
            if not slot then
                for s = 0, 19 do
                    if Claim(i, s) then break end
                end
            elseif PARTNER[slot] then
                Claim(i, PARTNER[slot])
            end
        end
    end
    -- In bags: a copy that already has the right enchant first.
    local bagLeft = {}
    for i, e in ipairs(items) do
        if not res[i] and snap.bag[e.id] then
            local left = bagLeft[e.id]
            if not left then
                left = {}
                for k, v in ipairs(snap.bag[e.id]) do left[k] = v end
                bagLeft[e.id] = left
            end
            if #left > 0 then
                local pick = 1
                if e.ench then
                    for k, en in ipairs(left) do
                        if en == e.ench.id then pick = k break end
                    end
                end
                local en = table.remove(left, pick)
                res[i] = { st = "bags", ench = en or nil }
            end
        end
    end
    -- In the bank. The game gives a count there, not the enchant.
    local bankLeft = {}
    for i, e in ipairs(items) do
        if not res[i] then
            local left = bankLeft[e.id] or math.max(0, Count(e.id, true) - Count(e.id))
            if left > 0 then
                res[i] = { st = "bank" }
                left = left - 1
            end
            bankLeft[e.id] = left
        end
    end

    local changed = false
    for i, e in ipairs(items) do
        local r = res[i]
        local st = r and r.st or nil
        local est = nil
        if e.ench and r then
            if r.ench ~= nil then
                est = (r.ench == e.ench.id)
            elseif st ~= "bank" then
                est = e.est -- link not in yet: keep the last answer
            end
        end
        if announce and db.announce then
            if st and st ~= "bank" and not e.st then
                NS.Print(("%s is on your list: %s, %s."):format(LinkOrName(e), set.name, NS.SlotLabel(e.slot)))
            elseif est == true and e.est == false and e.st then
                NS.Print(("%s is now on %s (%s)."):format(e.ench.name, LinkOrName(e), set.name))
            end
        end
        if st ~= e.st or est ~= e.est then changed = true end
        e.st, e.est = st, est
    end
    set.scanned = time()
    return changed
end

local announceReady = false -- off while a login is still filling in bags

function NS.ScanNow()
    local sets = NS.playerKey and db.sets[NS.playerKey]
    if not sets or #sets == 0 then return end
    local snap = Snapshot()
    local changed = false
    for _, set in ipairs(sets) do
        if CheckSet(set, snap, announceReady and set.scanned ~= nil) then changed = true end
    end
    if changed then NS.Changed() end
end

local queued = false
function NS.QueueScan()
    if queued then return end
    queued = true
    C_Timer.After(0.4, function()
        queued = false
        NS.ScanNow()
    end)
end

---------------------------------------------------------
--  SECTION: Item tooltips
---------------------------------------------------------
local function Index()
    if index then return index end
    index = {}
    for key, sets in pairs(db.sets) do
        for _, set in ipairs(sets) do
            for _, e in ipairs(set.items) do
                local refs = index[e.id] or {}
                index[e.id] = refs
                refs[#refs + 1] = { key = key, set = set, e = e }
            end
        end
    end
    for _, refs in pairs(index) do
        table.sort(refs, function(a, b)
            if (a.key == NS.playerKey) ~= (b.key == NS.playerKey) then return a.key == NS.playerKey end
            if a.key ~= b.key then return a.key < b.key end
            return a.set.name < b.set.name
        end)
    end
    return index
end
NS.ItemIndex = Index

local function OnTooltipItem(tooltip, data)
    if not db or not db.tooltip then return end
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip and tooltip ~= ShoppingTooltip1
        and tooltip ~= ShoppingTooltip2 then
        return
    end
    -- The list window's own rows already say all this.
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if owner and owner.gearListRow then return end
    local id = data and data.id
    if not id and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        id = LinkIDs(link)
    end
    local refs = type(id) == "number" and Index()[id]
    if not refs then return end
    for _, ref in ipairs(refs) do
        local where = ref.set.name .. ", " .. NS.SlotLabel(ref.e.slot)
        if ref.key ~= NS.playerKey then where = NS.CharName(ref.key) .. ": " .. where end
        if NS.ItemDone(ref.e) then
            tooltip:AddDoubleLine("Gear list", where .. " (have it)", 0.4, 0.8, 1, 0.6, 0.6, 0.6)
        else
            tooltip:AddDoubleLine("Gear list", where, 0.4, 0.8, 1, 0.3, 1, 0.3)
        end
    end
    tooltip:Show() -- resize to fit the new lines
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            pcall(OnTooltipItem, tooltip, data)
        end)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tip:HookScript("OnTooltipSetItem", function(self) pcall(OnTooltipItem, self) end)
        end
    end
end

---------------------------------------------------------
--  SECTION: Events and slash command
---------------------------------------------------------
local ev = CreateFrame("Frame")
for _, name in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
}) do
    pcall(ev.RegisterEvent, ev, name) -- an event this client doesn't have is skipped
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GearListDB = GearListDB or {}
        db = GearListDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                if type(v) == "table" then
                    db[k] = {}
                    for k2, v2 in pairs(v) do db[k][k2] = v2 end
                else
                    db[k] = v
                end
            end
        end
        db.summaryTab = nil -- 0.2's summary box is gone
        NS.db = db
    elseif not db then
        return
    elseif event == "PLAYER_LOGIN" then
        RegisterPlayer()
        HookTooltips()
    elseif event == "PLAYER_ENTERING_WORLD" then
        FollowSpec()
        NS.QueueScan()
        C_Timer.After(10, function() announceReady = true end)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then NS.QueueScan() end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
        -- A spec switch, or talents moved (which can rename a spec).
        QueueSpecs()
    else
        NS.QueueScan()
    end
end)

SLASH_GEARLIST1 = "/gearlist"
SLASH_GEARLIST2 = "/glist"
SLASH_GEARLIST3 = "/gl"
SlashCmdList.GEARLIST = function(msg)
    if not NS.playerKey then return end
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "import" then
        NS.ShowImport()
    elseif msg == "config" or msg == "settings" or msg == "options" then
        NS.ShowConfig()
    elseif msg == "help" or msg == "?" then
        NS.Print("|cffffd100/gl|r (or /gearlist) opens your lists, |cffffd100/gearlist import|r the paste window, "
            .. "|cffffd100/gearlist config|r the settings. /gl takes the same words.")
    else
        NS.ToggleMain()
    end
end
