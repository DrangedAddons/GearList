---------------------------------------------------------
--  GearList - settings window, launcher, Options page
--  Author: Dranged
---------------------------------------------------------
local ADDON, NS = ...
local UI = NS.UI
local ICON = "Interface\\AddOns\\GearList\\icon"
NS.ICON = ICON

local frame

local function Build()
    local db = NS.db
    frame = UI.Window({ name = "GearListConfig", title = "Gear List settings", width = 460, height = 414 })
    local body = frame.body

    local tip = UI.Check(body, "Say on item tooltips when an item is on a list",
        function() return db.tooltip end, function(v) db.tooltip = v end)
    tip:SetPoint("TOPLEFT", 0, 0)
    local say = UI.Check(body, "Say in chat when a listed item or enchant turns up",
        function() return db.announce end, function(v) db.announce = v end)
    say:SetPoint("TOPLEFT", 0, -28)
    local banner = UI.Check(body, "Show a banner when a listed item drops",
        function() return db.dropBanner end, function(v) db.dropBanner = v end)
    banner:SetPoint("TOPLEFT", 0, -56)
    local sound = UI.Check(body, "Play a sound when a listed item drops",
        function() return db.dropSound end, function(v) db.dropSound = v end)
    sound:SetPoint("TOPLEFT", 0, -84)
    local dropSay = UI.Check(body, "Say in chat when a listed item drops or someone else gets it",
        function() return db.dropChat end, function(v) db.dropChat = v end)
    dropSay:SetPoint("TOPLEFT", 0, -112)
    local done = UI.Check(body, "Show finished slots in the list",
        function() return db.showDone end, function(v) db.showDone = v; NS.Changed() end)
    done:SetPoint("TOPLEFT", 0, -140)
    local mm = UI.Check(body, "Show minimap button", function() return not db.minimap.hide end,
        function(v) UI.SetLauncherShown(db.minimap, v) end)
    mm:SetPoint("TOPLEFT", 0, -168)

    local y = -206
    if NS.HasEllesmere() then
        local label = UI.Text(body, "Window look", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 4, y)
        local look = UI.Dropdown(body, 260, function()
            local items = {}
            for _, o in ipairs(NS.LookOptions()) do items[#items + 1] = { value = o.value, label = o.text } end
            return items
        end, function() return db.theme end, function(v) NS.SetLook(v) end)
        look:SetPoint("TOPLEFT", 4, y - 16)
        y = y - 54
    end

    local about = UI.Text(body, "Lists are kept for the whole account, filed by character. Currency prices are built in; "
        .. "other vendor prices are written down when you open the vendor. Crafting materials come from CraftRoute, dungeon drops from "
        .. "DungeonJournal, other quests and drops from Questie and auction prices from Auctionator, when you have them.", "GameFontDisableSmall")
    about:SetPoint("TOPLEFT", 4, y)
    about:SetWidth(416)

    local close = UI.Button(body, "Close", 100, 24, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", 0, 0)
    local open = UI.Button(body, "Open the list", 130, 24, function() NS.ShowMain() end)
    open:SetPoint("BOTTOMLEFT", 0, 0)
    local test = UI.Button(body, "Test the drop alert", 150, 24, function() NS.TestDrop() end)
    test:SetPoint("LEFT", open, "RIGHT", 8, 0)
    frame.testDrop = test
end

function NS.ShowConfig()
    if not (NS.db and NS.playerKey) then return end
    if not frame then Build() end
    frame:Show()
    frame:Raise()
end

UI.RegisterSettingsPage(ICON, "/gearlist config", function() NS.ShowConfig() end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if not NS.db then return end
    UI.Launcher({
        icon = ICON,
        db = NS.db.minimap,
        onLeft = function() NS.ToggleMain() end,
        onRight = function() NS.ShowConfig() end,
        lines = { "|cffffd100/gl import|r to paste a new list" },
    })
end)
