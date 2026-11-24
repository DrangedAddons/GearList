"""Loads GearList against mock.lua (a stand-in for the WoW frame API) and runs
smoke.lua once per window look.

Usage: python tools/test/run.py [folder holding lupa]
  lupa: pip install lupa, or pip install lupa --target <folder> and pass the folder.

Exit code 1 when any look fails. The mock only proves the Lua runs and the
import, gear check and source logic hold; layout has to be checked in game.
"""
import os
import sys

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
import lupa.lua51 as lua

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ROOT = os.path.dirname(os.path.dirname(HERE)).replace("\\", "/")

bad = 0
for look in ("none", "eui"):
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    g.ADDON_DIR = ROOT
    g.HERE = HERE
    g.MOCK = HERE + "/mock.lua"
    g.LOOK = look
    try:
        rt.execute(
            'local ok, err = xpcall(function() dofile("%s/smoke.lua") end, debug.traceback) '
            "if not ok then Say(err) FAILS = 999 end" % HERE
        )
    except Exception as e:
        print("ERROR", e)
        bad += 1
        continue
    if g.FAILS != 0:
        bad += 1
print("looks failed:", bad)
sys.exit(1 if bad else 0)
