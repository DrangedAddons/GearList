-- Minimal WoW frame API mock: enough to run the hub's own Lua end to end.
-- Globals in: ADDON_DIR, LOOK ("none" | "eui" | "forever" | "classic")
local allFrames = {}
local timers = {}
local M = {}
local NIL_KEYS = { Text = true, Left = true, Middle = true, Right = true, Center = true }

local MT = {}
MT.__index = function(t, k)
    local m = M[k]
    if m then return m end
    if type(k) ~= "string" or NIL_KEYS[k] or not k:match("^%u") then return nil end
    if k:match("^Create") then
        return function(self) return NewObj("Region", nil, self, true) end
    end
    if k:match("^Is") or k:match("^Has") then return function() return false end end
    return function() end
end

function NewObj(kind, name, parent, isRegion)
    local o = { _type = kind, _shown = true, _scripts = {}, _children = {}, _regions = {}, _w = 0, _h = 0,
        _scale = 1, _level = 1, _events = {}, _points = {}, _isRegion = isRegion, _name = name }
    setmetatable(o, MT)
    if parent then
        o._parent = parent
        table.insert(isRegion and parent._regions or parent._children, o)
    end
    if name then _G[name] = o end
    if not isRegion then allFrames[#allFrames + 1] = o end
    return o
end

local function Visible(o)
    while o do
        if not o._shown then return false end
        o = o._parent
    end
    return true
end
local function Fire(o, script, ...)
    local s = o._scripts[script]
    if s then s(o, ...) end
end
local function Snapshot(o, out)
    out = out or {}
    out[o] = Visible(o)
    for _, c in ipairs(o._children) do Snapshot(c, out) end
    return out
end
local function Diff(o, before)
    for f, was in pairs(before) do
        local now = Visible(f)
        if now ~= was then Fire(f, now and "OnShow" or "OnHide") end
    end
end

function M.Show(o) local b = Snapshot(o); o._shown = true; Diff(o, b) end
function M.Hide(o) local b = Snapshot(o); o._shown = false; Diff(o, b) end
function M.SetShown(o, on) local b = Snapshot(o); o._shown = on and true or false; Diff(o, b) end
function M.IsShown(o) return o._shown end
function M.IsVisible(o) return Visible(o) end
function M.SetScript(o, k, f) o._scripts[k] = f end
function M.GetScript(o, k) return o._scripts[k] end
function M.HookScript(o, k, f)
    local old = o._scripts[k]
    o._scripts[k] = old and function(...) old(...); f(...) end or f
end
function M.SetParent(o, p)
    local b = Snapshot(o)
    if o._parent then
        local list = o._isRegion and o._parent._regions or o._parent._children
        for i, c in ipairs(list) do if c == o then table.remove(list, i) break end end
    end
    o._parent = p
    if p then table.insert(o._isRegion and p._regions or p._children, o) end
    Diff(o, b)
end
function M.GetParent(o) return o._parent end
local function Sized(o, w, h)
    local changed = (w ~= o._w) or (h ~= o._h)
    o._w, o._h = w, h
    if changed then Fire(o, "OnSizeChanged", w, h) end
end
function M.SetSize(o, w, h) Sized(o, w, h) end
function M.SetWidth(o, w) Sized(o, w, o._h) end
function M.SetHeight(o, h) Sized(o, o._w, h) end
-- Anchors are resolved for real (no scale): left, top, right, bottom, or nil
-- when the object isn't anchored to anything.
local function Rect(o, depth)
    depth = depth or 0
    if depth > 30 then return nil end
    if o == UIParent then return 0, 1200, 4266, 0 end
    local w, h = o._w, o._h
    if o._type == "FontString" then
        if w == 0 then w = #(tostring(o._text or "")) * 7 end
        if h == 0 then h = 12 end
    end
    if o._scrollOf then   -- a scroll frame's content sits at its top left
        local l, t = Rect(o._scrollOf, depth + 1)
        if not l then return nil end
        return l, t, l + w, t - h
    end
    local L, T, R, B, CX, CY
    for _, p in ipairs(o._points) do
        local rl, rt, rr, rb = Rect(p[2] or o._parent or UIParent, depth + 1)
        if rl then
            local rp = p[3]
            local x = rp:find("LEFT") and rl or rp:find("RIGHT") and rr or (rl + rr) / 2
            local y = rp:find("TOP") and rt or rp:find("BOTTOM") and rb or (rt + rb) / 2
            x, y = x + p[4], y + p[5]
            if p[1]:find("LEFT") then L = x elseif p[1]:find("RIGHT") then R = x else CX = x end
            if p[1]:find("TOP") then T = y elseif p[1]:find("BOTTOM") then B = y else CY = y end
        end
    end
    if not (L and R) then
        if L then R = L + w elseif R then L = R - w elseif CX then L, R = CX - w / 2, CX + w / 2 else return nil end
    end
    if not (T and B) then
        if T then B = T - h elseif B then T = B + h elseif CY then T, B = CY + h / 2, CY - h / 2 else return nil end
    end
    return L, T, R, B
end
function M.GetWidth(o)
    if o._w == 0 then
        local l, _, r = Rect(o)
        if l then return r - l end
    end
    return o._w
end
function M.GetHeight(o)
    if o._h == 0 then
        local l, t, _, b = Rect(o)
        if l then return t - b end
    end
    return o._h
end
function M.GetSize(o) return o:GetWidth(), o:GetHeight() end
function M.SetPoint(o, point, a, b, c, d)
    assert(type(point) == "string", "SetPoint: point must be a string")
    local rel, relPoint, x, y
    if type(a) == "number" then
        x, y = a, b
    elseif type(a) == "table" then
        rel = a
        if type(b) == "string" then relPoint, x, y = b, c, d else x, y = b, c end
    end
    local p = { point, rel, relPoint or point, x or 0, y or 0 }
    for i, old in ipairs(o._points) do
        if old[1] == point then o._points[i] = p return end
    end
    o._points[#o._points + 1] = p
end
function M.SetAllPoints(o, rel)
    o._points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function M.ClearAllPoints(o) o._points = {} end
function M.GetNumPoints(o) return #o._points end
function M.GetPoint(o, i)
    local p = o._points[i or 1]
    if p then return p[1], p[2] or o._parent, p[3], p[4], p[5] end
end
function M.GetChildren(o) return unpack(o._children) end
function M.GetRegions(o) return unpack(o._regions) end
function M.GetObjectType(o) return o._type end
function M.GetName(o) return o._name end
function M.SetText(o, t) o._text = t end
function M.GetText(o) return o._text end
function M.GetStringWidth(o) return #(tostring(o._text or "")) * 7 end
function M.GetStringHeight() return 12 end
function M.GetTextWidth(o) return #(tostring(o._text or "")) * 7 end
function M.SetScale(o, s) assert(type(s) == "number" and s > 0, "bad scale"); o._scale = s end
function M.GetScale(o) return o._scale end
function M.GetEffectiveScale(o) return o._scale end
function M.SetFrameLevel(o, l) assert(type(l) == "number", "bad level"); o._level = l end
function M.GetFrameLevel(o) return o._level end
function M.GetFrameStrata() return "DIALOG" end
function M.SetFrameStrata(o, s) assert(type(s) == "string", "bad strata") end
function M.GetTop(o) local _, t = Rect(o); return t end
function M.GetBottom(o) local _, _, _, b = Rect(o); return b end
function M.GetLeft(o) local l = Rect(o); return l end
function M.GetRight(o) local _, _, r = Rect(o); return r end
function M.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function M.SetFont() return true end
function M.GetHighlightTexture(o) o._hl = o._hl or NewObj("Texture", nil, o, true); return o._hl end
function M.GetNormalTexture(o) return nil end
function M.GetPushedTexture(o) return nil end
function M.GetDisabledTexture(o) return nil end
function M.GetThumbTexture(o) o._thumb = o._thumb or NewObj("Texture", nil, o, true); return o._thumb end
function M.GetFontString(o) o._fs = o._fs or NewObj("FontString", nil, o, true); return o._fs end
function M.CreateTexture(o) return NewObj("Texture", nil, o, true) end
function M.CreateFontString(o) return NewObj("FontString", nil, o, true) end
function M.CreateLine(o) return NewObj("Line", nil, o, true) end
function M.RegisterEvent(o, e) o._events[e] = true end
function M.GetVerticalScroll(o) return o._scroll or 0 end
function M.SetVerticalScroll(o, v) assert(type(v) == "number"); o._scroll = v end
function M.GetHorizontalScroll(o) return o._hscroll or 0 end
function M.SetHorizontalScroll(o, v) assert(type(v) == "number"); o._hscroll = v end
function M.SetScrollChild(o, c) o._scrollChild = c; c._scrollOf = o end
function M.GetValue(o) return o._value or 0 end
function M.SetValue(o, v) o._value = v; Fire(o, "OnValueChanged", v) end
function M.GetChecked(o) return o._checked end
function M.SetChecked(o, v) o._checked = v end
function M.HasFocus() return false end
function M.IsEnabled() return true end
function M.Click(o, button) Fire(o, "OnClick", button or "LeftButton") end
function M.StartMoving() end
function M.StopMovingOrSizing() end

function CreateFrame(kind, name, parent, template)
    local o = NewObj(kind, name, parent, false)
    if template and template:find("Backdrop") then
        o.SetBackdrop = function(self, bd) self.backdropInfo = bd end
        o.SetBackdropColor = function() end
        o.SetBackdropBorderColor = function() end
    end
    return o
end

function hooksecurefunc(a, b, c)
    local tbl, name, hook = a, b, c
    if type(a) == "string" then tbl, name, hook = _G, a, b end
    local orig = tbl[name]
    assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
    rawset(tbl, name, function(...)
        local r = { orig(...) }
        hook(...)
        return unpack(r)
    end)
end

UIParent = NewObj("Frame", "UIParent")
UIParent._w, UIParent._h = 4266, 1200
Minimap = NewObj("Frame", "Minimap", UIParent)
GameTooltip = NewObj("GameTooltip", "GameTooltip", UIParent)
ColorPickerFrame = NewObj("Frame", "ColorPickerFrame", UIParent)
SettingsPanel = NewObj("Frame", "SettingsPanel", UIParent)
SettingsPanel._shown = false
GameFontHighlight = NewObj("Font")
UISpecialFrames = {}
-- Like the client: commands can be set and looked up by key, but walking the
-- list with pairs() finds nothing.
do
    local store = {}
    SlashCmdList = setmetatable({}, { __index = store, __newindex = store })
end
CLOSE = "Close"
tinsert = table.insert
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function InCombatLockdown() return false end
function HideUIPanel(f) f:Hide() end
function UnitName() return "Tester" end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return 0, 0 end
RELOADS = 0
function ReloadUI() RELOADS = RELOADS + 1 end
PRINTED = {}
local realPrint = print
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    PRINTED[#PRINTED + 1] = table.concat(t, " ")
end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() end }
function FlushTimers()
    local n = 0
    while #timers > 0 and n < 100 do
        local fn = table.remove(timers, 1)
        fn()
        n = n + 1
    end
end

Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) panel:Hide(); return { GetID = function() return name end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

-- Libraries
local dbi = { objects = {} }
function dbi:Register(name, obj, db)
    local b = NewObj("Button", nil, Minimap)
    b.db = db
    b._shown = not (db and db.hide)
    self.objects[name] = b
end
function dbi:GetMinimapButton(name) return self.objects[name] end
function dbi:Show(name) self.objects[name]:Show() end
function dbi:Hide(name) self.objects[name]:Hide() end
local ldb = { NewDataObject = function(_, name, t) return t end }
local libs = { ["LibDBIcon-1.0"] = dbi, ["LibDataBroker-1.1"] = ldb }
LibStub = setmetatable({}, { __call = function(_, name) return libs[name] end })
DBI = dbi

-- Addon list
ADDONS = {
    { "CastCount", "CastCount", "Casts left", { Author = "Dranged", Version = "3.0.0", IconTexture = "Interface\\Icons\\X", ["X-DrangedAddons-Games"] = "_forever_",
        -- its .toc names a command the mock can't run: the hub has to fall back to its built-in opener
        ["X-DrangedHub-Frame"] = "CastCountConfig", ["X-DrangedHub-Open"] = "/castcount", ["X-DrangedHub-Crop"] = "34" }, true },
    { "CraftRoute", "CraftRoute", "Routes", { Author = "Dranged + Lexible", Version = "1.17.2" }, true },
    { "DrangedHub", "DrangedAddons", "Hub", { Author = "Dranged", Version = "0.1.0" }, true },
    { "EscortReady", "EscortReady", "Escort", { Author = "Dranged", Version = "0.13.0" }, true },
    { "FishIO", "FishIO", "Fishing", { Author = "Dranged", Version = "0.1.0" }, true },
    { "GuessAddon", "GuessAddon", "Says nothing about itself", { Author = "Dranged", Version = "1.0.0" }, true },
    { "HoTProbe", "HoTProbe", "Probe", { Author = "Dranged", Version = "0.2.0" }, true },
    { "Questie", "Questie", "Quests", { Author = "Someone" }, true },
    { "LuaAddon", "LuaAddon", "Describes itself in Lua", { Author = "Dranged", Version = "1.0.0" }, true },
    { "TocAddon", "TocAddon", "Describes itself in its .toc", { Author = "Dranged", Version = "2.0.0",
        ["X-DrangedHub-Frame"] = "TocAddonWin", ["X-DrangedHub-Open"] = "/tocaddon config",
        ["X-DrangedHub-Actions"] = "Main window=/tocaddon; Preview = /tocaddon preview [keep]",
        ["X-DrangedHub-Tool"] = "1" }, true },
    { "TooltipExtras", "|cff33ff99TooltipExtras|r", "Tooltips", { Author = "Dranged", Version = "0.31.0" }, true },
    { "VendorPoint", "VendorPoint", "Vendors", { Author = "Dranged", Version = "1.2.0" }, true },
    { "ZoneStyle", "ZoneStyle", "Zone text", { Author = "Dranged", Version = "1.0.0" }, false },
}
ENABLED = {}
local function Find(x)
    if type(x) == "number" then return ADDONS[x] end
    for _, a in ipairs(ADDONS) do if a[1] == x then return a end end
end
C_AddOns = {
    GetNumAddOns = function() return #ADDONS end,
    GetAddOnInfo = function(i) local a = Find(i); return a[1], a[2], a[3] end,
    GetAddOnMetadata = function(n, field) local a = Find(n); return a and a[4][field] end,
    IsAddOnLoaded = function(n) local a = Find(n); return a and a[5] end,
    GetAddOnEnableState = function(n) if ENABLED[n] ~= nil then return ENABLED[n] and 2 or 0 end local a = Find(n); return (a and a[5]) and 2 or 0 end,
    EnableAddOn = function(n) ENABLED[n] = true end,
    DisableAddOn = function(n) ENABLED[n] = false end,
}

if LOOK ~= "none" then
    EllesmereUI = {
        ELLESMERE_GREEN = { r = 0.05, g = 0.82, b = 0.62 },
        IS_FOREVER = true,
        RenderedLook = function() return LOOK end,
    }
    NineSliceUtil = { ApplyLayoutByName = function() end }
end

function FireEvent(event, ...)
    for i = 1, #allFrames do
        local f = allFrames[i]
        if f._events[event] then Fire(f, "OnEvent", event, ...) end
    end
end

local function ReadFile(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end
function LoadAddon(dir, name, files)
    local ns = {}
    for _, file in ipairs(files) do
        local chunk = assert(loadstring(ReadFile(dir .. "/" .. file), "=" .. file))
        chunk(name, ns)
    end
    return ns
end
function Say(...) realPrint(...) end
