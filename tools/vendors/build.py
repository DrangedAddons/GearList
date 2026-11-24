"""Builds Data/Vendors.lua, the built-in vendor price table, from the files beside this script.

Usage: python tools/vendors/build.py

Inputs, all saved by hand from Wowhead's Forever database (wowhead.com/forever):

  gear.txt   Every weapon and armor piece of uncommon quality or better that a vendor sells,
             from the item lists filtered to "Sold by vendor". Its header says which pages
             and explains the line format. Each line ends in a count and sums; a line that
             doesn't add up stops the build.

  *.json     A currency page's "Currency for" list, in one of two shapes:
               { "source": url, "collected": date, "zones": { id: name }, "currencies": { id: name },
                 "rows": [ [itemID, name, cost, vendor, vendorID, zoneID, source, sources, class, slot], ... ] }
               { "source": ..., "collected": ..., "currencies": ...,
                 "groups": [ [way, [itemID, ...]], ... ] }     gear only, grouped by price
             These are read after gear.txt and win where both have an item. They also supply
             the currency names and any zone names.

A cost is Wowhead's: a list of ways to pay; a way is [copper, [[currencyID, n], ...], [[itemID, n], ...]].
An item with more than one way gets the first that asks for a currency, else the first.
Only gear (item class 2 weapons, 4 armor) goes in. A seller is named only when Wowhead's
source for the item is a vendor alone. Token items (marks and the like) are stored by ID and
zones by ID; the game supplies their names. In game, a price read off a merchant window
always wins over this table.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def pick(cost):
    """The way to pay that goes in the table."""
    return next((w for w in cost if w[1]), cost[0])


# item id -> (vendor, copper, way key, name)   vendor = (name, zoneID, zoneName) or None
items = {}
sources = []
currencies = {}


def add(item_id, vendor, way, name=None):
    key = json.dumps([way[1], way[2]], separators=(",", ":"))
    items[item_id] = (vendor, way[0] or None, key, name)


# The currency lists first for their names; gear.txt needs them.
json_files = sorted(glob.glob(os.path.join(HERE, "*.json")))
loaded = [json.load(open(p, encoding="utf-8")) for p in json_files]
for data in loaded:
    currencies.update({int(k): v for k, v in data.get("currencies", {}).items()})

gear = os.path.join(HERE, "gear.txt")
if os.path.exists(gear):
    vendors = {}
    for ln, line in enumerate(open(gear, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if line.startswith("# Wowhead") or line.startswith("# Pages") or line.startswith("# Collected"):
            sources.append(line[2:])
        if not line or line.startswith("#"):
            continue
        f = line.split("|")
        if f[0] == "V":
            vendors[f[1]] = (f[2], int(f[4]) or None, None)
        elif f[0] == "C":
            ids = [int(x) for x in f[3].split(",")]
            if len(ids) != int(f[4]) or sum(ids) != int(f[5]):
                sys.exit("gear.txt line %d doesn't add up" % ln)
            way = json.loads(f[2])
            for item_id in ids:
                add(item_id, vendors.get(f[1]), way)
        elif f[0] == "G":
            pairs = [tuple(int(y) for y in x.split(":")) for x in f[2].split(",")]
            if len(pairs) != int(f[3]) or sum(p[0] for p in pairs) != int(f[4]) or sum(p[1] for p in pairs) != int(f[5]):
                sys.exit("gear.txt line %d doesn't add up" % ln)
            for item_id, copper in pairs:
                add(item_id, vendors.get(f[1]), [copper, [], []])
        else:
            sys.exit("gear.txt line %d: unknown kind %r" % (ln, f[0]))

for data in loaded:
    sources.append("%s, %s" % (data["source"], data["collected"]))
    zones = data.get("zones", {})
    rows = list(data.get("rows", []))
    for way, ids in data.get("groups", []):
        # A grouped list has no sellers: keep the one gear.txt found, if any.
        rows += [[i, None, [way], None, None, None, None, 0, 4, 0] for i in ids]
    for item_id, name, cost, vendor, _vendor_id, zone, source, _n, cls, _slot in rows:
        if cls not in (2, 4) or not cost:
            continue
        seller = None
        if source == [5] and vendor:
            seller = (vendor, zone, zones.get(str(zone)))
        elif item_id in items:
            seller = items[item_id][0]
        add(item_id, seller, pick(cost), name)

# Sellers and ways repeat a lot, so each is written once and pointed at.
seller_ids, way_ids = {}, {}
for item_id in sorted(items):
    vendor, _copper, key, _name = items[item_id]
    if vendor and vendor not in seller_ids:
        seller_ids[vendor] = len(seller_ids) + 1
    if key != "[[],[]]" and key not in way_ids:
        way_ids[key] = len(way_ids) + 1

out = [
    "-- Generated by tools/vendors/build.py - do not edit by hand.",
    "-- Vendor prices for gear, from Wowhead's Forever database:",
]
out += ["--   " + s for s in sources]
out += [
    "-- Each entry has the shape of a price GearList reads off a merchant window (and those win over these):",
    "--   { npc, zoneID, zone, gold (copper), costs = { { cur = currency ID, name, n } or { id = item ID, n }, ... } }",
    "local _, NS = ...",
    "",
    "-- Sellers: name, zone ID, zone name (when the source gave one)",
    "local S = {",
]
for vendor, n in sorted(seller_ids.items(), key=lambda kv: kv[1]):
    name, zone_id, zone_name = vendor
    out.append("  [%d] = { %s, %s, %s }," % (n, lua_str(name), zone_id or "nil", lua_str(zone_name) if zone_name else "nil"))
out += ["}", "", "-- Currency and token costs", "local W = {"]
for key, n in sorted(way_ids.items(), key=lambda kv: kv[1]):
    curs, tokens = json.loads(key)
    bits = ["{ cur = %d, name = %s, n = %d }" % (c, lua_str(currencies.get(c, "currency %d" % c)), q) for c, q in curs]
    bits += ["{ id = %d, n = %d }" % (t, q) for t, q in tokens]
    out.append("  [%d] = { %s }," % (n, ", ".join(bits)))
out += [
    "}",
    "local NONE = {}",
    "",
    "-- seller index, copper, cost index",
    "local function R(s, gold, w)",
    "    s = s and S[s]",
    "    return { npc = s and s[1] or nil, zoneID = s and s[2] or nil, zone = s and s[3] or nil,",
    "        gold = gold, costs = w and W[w] or NONE }",
    "end",
    "",
    "NS.VENDORS = {",
]
for item_id in sorted(items):
    vendor, copper, key, name = items[item_id]
    out.append("  [%d] = R(%s, %s, %s),%s" % (
        item_id, seller_ids.get(vendor, "nil"), copper or "nil", way_ids.get(key, "nil"), name and (" -- " + name) or ""))
out.append("}")
with open(os.path.join(ROOT, "Data", "Vendors.lua"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(out) + "\n")
print("wrote Data/Vendors.lua: %d items, %d sellers, %d costs" % (len(items), len(seller_ids), len(way_ids)))
