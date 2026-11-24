---------------------------------------------------------
--  GearList - JSON reader
--  Author: Dranged
---------------------------------------------------------
-- Reads the text sixtyupgrades.com exports. Decode(text) returns a Lua value or
-- raises a string error; callers pcall it. null becomes nil in an object and
-- false in a list (so list positions hold).

local ADDON, NS = ...
local Json = {}
NS.Json = Json

local MAX_DEPTH = 64
local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function Fail(what, i)
    error(what .. " at character " .. i, 0)
end

local function Utf8(cp)
    local floor, char = math.floor, string.char
    if cp < 0x80 then
        return char(cp)
    elseif cp < 0x800 then
        return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
        0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local function SkipSpace(s, i)
    return s:find("[^ \t\r\n]", i) or (#s + 1)
end

-- i is the opening quote. Returns the string and the position after the closing quote.
local function ReadString(s, i)
    local out, n, j = {}, 0, i + 1
    while true do
        local k = s:find('["\\]', j)
        if not k then Fail("text that never ends", i) end
        if k > j then n = n + 1; out[n] = s:sub(j, k - 1) end
        if s:sub(k, k) == '"' then return table.concat(out), k + 1 end
        local c = s:sub(k + 1, k + 1)
        if c == "u" then
            local hex = s:match("^%x%x%x%x", k + 2)
            if not hex then Fail("a bad \\u code", k) end
            local cp = tonumber(hex, 16)
            j = k + 6
            -- Two \u codes in a row can be one character (a surrogate pair).
            if cp >= 0xD800 and cp <= 0xDBFF then
                local lo = s:match("^\\u(%x%x%x%x)", j)
                lo = lo and tonumber(lo, 16)
                if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    j = j + 6
                end
            end
            n = n + 1; out[n] = Utf8(cp)
        else
            local r = ESC[c]
            if not r then Fail("a bad \\ code", k) end
            n = n + 1; out[n] = r
            j = k + 2
        end
    end
end

local ReadValue

local function ReadList(s, i, depth)
    local list, n = {}, 0
    i = SkipSpace(s, i + 1)
    if s:sub(i, i) == "]" then return list, i + 1 end
    while true do
        local v
        v, i = ReadValue(s, i, depth)
        n = n + 1
        if v == nil then list[n] = false else list[n] = v end
        i = SkipSpace(s, i)
        local c = s:sub(i, i)
        if c == "]" then return list, i + 1 end
        if c ~= "," then Fail("a missing , or ]", i) end
        i = SkipSpace(s, i + 1)
    end
end

local function ReadObject(s, i, depth)
    local obj = {}
    i = SkipSpace(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
        if s:sub(i, i) ~= '"' then Fail("a missing name", i) end
        local key
        key, i = ReadString(s, i)
        i = SkipSpace(s, i)
        if s:sub(i, i) ~= ":" then Fail("a missing :", i) end
        local v
        v, i = ReadValue(s, SkipSpace(s, i + 1), depth)
        obj[key] = v
        i = SkipSpace(s, i)
        local c = s:sub(i, i)
        if c == "}" then return obj, i + 1 end
        if c ~= "," then Fail("a missing , or }", i) end
        i = SkipSpace(s, i + 1)
    end
end

function ReadValue(s, i, depth)
    depth = depth + 1
    if depth > MAX_DEPTH then Fail("too many nested levels", i) end
    local c = s:sub(i, i)
    if c == "{" then return ReadObject(s, i, depth) end
    if c == "[" then return ReadList(s, i, depth) end
    if c == '"' then return ReadString(s, i) end
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    if s:sub(i, i + 3) == "null" then return nil, i + 4 end
    local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
    local v = num and tonumber(num)
    if not v then
        if i > #s then Fail("text that stops early", i) end
        Fail("something unexpected", i)
    end
    return v, i + #num
end

function Json.Decode(text)
    if type(text) ~= "string" then error("no text", 0) end
    -- A byte-order mark sometimes rides along with copied text.
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
    local i = SkipSpace(text, 1)
    if i > #text then error("no text", 0) end
    local v
    v, i = ReadValue(text, i, 0)
    i = SkipSpace(text, i)
    if i <= #text then Fail("extra text after the end", i) end
    return v
end
