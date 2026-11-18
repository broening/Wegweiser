import sys, glob, os
from lupa.luajit21 import LuaRuntime
lua = LuaRuntime()
check = lua.eval("function(src, name) local f, err = loadstring(src, name); return err end")
root = sys.argv[1]
bad = 0
n = 0
for p in sorted(glob.glob(os.path.join(root, "**", "*.lua"), recursive=True)):
    n += 1
    src = open(p, "rb").read()
    err = check(src, "@" + os.path.relpath(p, root))
    if err:
        bad += 1
        print("FEHLER", err)
print(n, "Dateien geprueft, Fehler:", bad)
