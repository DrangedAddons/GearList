---------------------------------------------------------
--  GearList - the import window
--  Author: Dranged
---------------------------------------------------------
-- Paste the Export text, pick who it's for, name it, import.

local ADDON, NS = ...
local UI = NS.UI

local frame, edit, scroll, placeholder, preview, importBtn

-- char is a "Name-Realm" key, or "@export" (the name inside the export) or
-- "@typed" (a name typed in) for a character the addon hasn't been logged in on.
local st = { text = nil, parsed = nil, err = nil, char = nil, name = "", typedName = nil }

local function TargetName()
    if st.char == "@export" then return st.parsed and st.parsed.forName end
    if st.char == "@typed" then return st.typedName end
    return NS.CharName(st.char)
end

-- The saved key for the chosen character, when it has one already.
local function TargetKey()
    if st.char == "@export" then return st.parsed and NS.FindChar(st.parsed.forName) end
    if st.char == "@typed" then return NS.FindChar(st.typedName) end
    return st.char
end

local function Reparse(force)
    local text = edit:GetText() or ""
    if not force and text == st.text then return end
    st.text = text
    if not text:find("%S") then
        st.parsed, st.err = nil, nil
    else
        st.parsed, st.err = NS.ParseExport(text)
    end
    if st.parsed then
        st.name = st.parsed.name
        -- The character the export was made for, when that's one of yours; otherwise this one.
        st.char = NS.FindChar(st.parsed.forName) or NS.playerKey
    elseif st.char == "@export" then
        st.char = NS.playerKey
    end
    UI.RefreshAll()
end

local function DoImport()
    Reparse(true)
    local set = st.parsed
    if not set then return end
    local key = st.char
    if key == "@export" then key = NS.AddTypedChar(set.forName) end
    if key == "@typed" then key = NS.AddTypedChar(st.typedName) end
    if not key or not NS.db.chars[key] then return end

    local name = (st.name or ""):match("^%s*(.-)%s*$")
    if name == "" then name = set.name end
    local saved, replaced = NS.SaveSet(key, set, name)
    local _, total, _, eTotal = NS.Progress(saved)
    NS.Print(("%s \"%s\" for %s: %d items, %d enchants."):format(
        replaced and "Replaced" or "Imported", saved.name, NS.CharName(key), total, eTotal))

    -- The saved table is the parsed one, so drop it here before anything else can reuse it.
    st.parsed, st.err, st.text, st.name = nil, nil, "", ""
    edit:SetText("")
    frame:Hide()
    NS.ShowMain(key, saved.name)
end

StaticPopupDialogs["GEARLIST_OTHER_CHAR"] = {
    text = "Character name (on this realm):",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 24,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        local name = box and box:GetText() or ""
        name = name:gsub("|", ""):gsub("%s+", "")
        if name ~= "" then
            st.typedName = name
            st.char = NS.FindChar(name) or "@typed"
            UI.RefreshAll()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local button = parent.button1 or (parent.GetButton1 and parent:GetButton1())
        if button then button:Click() end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Targets()
    local items = {}
    for _, key in ipairs(NS.CharList()) do
        items[#items + 1] = { value = key, label = NS.CharLabel(key) }
    end
    local forName = st.parsed and st.parsed.forName
    if forName and not NS.FindChar(forName) then
        items[#items + 1] = { value = "@export", label = forName .. " |cff808080(named in the export)|r" }
    end
    if st.typedName and not NS.FindChar(st.typedName) then
        items[#items + 1] = { value = "@typed", label = st.typedName .. " |cff808080(not logged in yet)|r" }
    end
    items[#items + 1] = { value = "@other", label = "Another character..." }
    return items
end

local function Refresh()
    if not frame:IsShown() then return end
    placeholder:SetShown((edit:GetText() or "") == "")
    local set = st.parsed
    importBtn:SetEnabled(set ~= nil)
    if not set then
        importBtn:SetText("Import")
        if st.err and (edit:GetText() or ""):find("%S") then
            preview:SetText("|cffff6060" .. st.err .. "|r")
        else
            preview:SetText("|cff9d9d9dNothing pasted yet.|r")
        end
        return
    end

    local enchants, marked = 0, 0
    for _, e in ipairs(set.items) do
        if e.ench then enchants = enchants + 1 end
        if e.mark then marked = marked + 1 end
    end
    local head = "|cffffd100" .. set.name .. "|r"
    if set.phase then head = head .. "   Phase " .. set.phase end
    if set.class then head = head .. "   " .. NS.ClassName(set.class) end
    if set.level then head = head .. " " .. set.level end
    local lines = { head, ("%d items, %d enchants%s."):format(#set.items, enchants,
        marked > 0 and (", " .. marked .. " ticked as acquired on the site") or "") }
    if set.forName then lines[#lines + 1] = "Exported for " .. set.forName .. "." end

    local key = TargetKey()
    local c = key and NS.db.chars[key]
    if set.class and c and c.class and c.class ~= set.class then
        lines[#lines + 1] = ("|cffffa040%s is a %s; this list was made for a %s.|r"):format(
            c.name, NS.ClassName(c.class), NS.ClassName(set.class))
    end
    local name = (st.name or ""):match("^%s*(.-)%s*$")
    if name == "" then name = set.name end
    local old = key and NS.FindSet(key, name)
    if old then
        lines[#lines + 1] = ("|cffffa040%s already has a list called \"%s\". Importing replaces it; "
            .. "hand ticks stay on slots that didn't change.|r"):format(TargetName() or "?", old.name)
    end
    importBtn:SetText(old and "Replace" or "Import")
    preview:SetText(table.concat(lines, "\n"))
end

local function Build()
    frame = UI.Window({ name = "GearListImport", title = "Import a gear list", width = 640, height = 600 })
    local body = frame.body
    local bodyW = 640 - 36

    local how = UI.Text(body, "On |cffffd100sixtyupgrades.com/forever|r open your set, click |cffffd100Export|r "
        .. "and copy all of the text. Click in the box below and press |cffffd100Ctrl+V|r.", "GameFontHighlight")
    how:SetPoint("TOPLEFT", 0, 0)
    how:SetWidth(bodyW)

    local box = CreateFrame("Frame", nil, body, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, -40)
    box:SetSize(bodyW, 250)
    UI.Backdrop(box, 0.03, 0.03, 0.035, 0.95)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)

    local inner = CreateFrame("Frame", nil, box)
    inner:SetPoint("TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", -6, 6)
    local content
    scroll, content = UI.ScrollArea(inner, bodyW - 28)

    edit = CreateFrame("EditBox", nil, content)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    if edit.SetMaxBytes then edit:SetMaxBytes(0) end
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetPoint("TOPLEFT")
    edit:SetWidth(bodyW - 28)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    placeholder = UI.Text(box, "Click here, then Ctrl+V", "GameFontDisable")
    placeholder:SetPoint("CENTER")

    -- A paste arrives as a burst of changes; read it once it settles.
    local settle
    edit:SetScript("OnTextChanged", function(self)
        scroll:SetContentHeight(math.max(self:GetHeight() or 0, scroll:GetHeight() or 0))
        placeholder:SetShown((self:GetText() or "") == "")
        settle = 0.25
    end)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
        if not self:HasFocus() then return end
        local top, viewH, cur = -(y or 0), scroll:GetHeight() or 0, scroll:GetVerticalScroll() or 0
        if top < cur then
            scroll:ScrollTo(top)
        elseif top + (h or 0) > cur + viewH then
            scroll:ScrollTo(top + (h or 0) - viewH)
        end
    end)
    frame:SetScript("OnUpdate", function(_, dt)
        if not settle then return end
        settle = settle - dt
        if settle <= 0 then
            settle = nil
            Reparse()
        end
    end)

    preview = UI.Text(body, "", "GameFontHighlight")
    preview:SetPoint("TOPLEFT", 0, -300)
    preview:SetWidth(bodyW)
    preview:SetJustifyV("TOP")
    preview:SetHeight(112)

    local forLabel = UI.Text(body, "Apply to", "GameFontNormal")
    forLabel:SetPoint("BOTTOMLEFT", 0, 46)
    local charDD = UI.Dropdown(body, 250, Targets, function()
        if not st.char then st.char = NS.playerKey end
        return st.char
    end, function(v)
        if v == "@other" then
            StaticPopup_Show("GEARLIST_OTHER_CHAR")
        else
            st.char = v
        end
    end)
    charDD:SetPoint("LEFT", forLabel, "RIGHT", 10, 0)

    local nameLabel = UI.Text(body, "List name", "GameFontNormal")
    nameLabel:SetPoint("LEFT", charDD, "RIGHT", 22, 0)
    local nameEdit = UI.Edit(body, 170, false, function() return st.name or "" end, function(v)
        st.name = v
        UI.RefreshAll()
    end)
    nameEdit:SetMaxLetters(40)
    nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 14, 0)

    local close = UI.Button(body, "Close", 100, 24, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", 0, 0)
    local clear = UI.Button(body, "Clear", 100, 24, function()
        edit:SetText("")
        Reparse(true)
        edit:SetFocus()
    end)
    clear:SetPoint("RIGHT", close, "LEFT", -6, 0)
    importBtn = UI.Button(body, "Import", 130, 24, DoImport)
    importBtn:SetPoint("BOTTOMLEFT", 0, 0)

    UI.Track({ Refresh = Refresh })
    -- Ready for Ctrl+V as soon as it opens.
    frame:HookScript("OnShow", function() edit:SetFocus() end)
end

function NS.ShowImport()
    if not (NS.db and NS.playerKey) then return end
    if not frame then Build() end
    if not st.char or (st.char:sub(1, 1) ~= "@" and not NS.db.chars[st.char]) then st.char = NS.playerKey end
    frame:Show()
    frame:Raise()
end
