"""Run with JPype1 and the installed game directory as the only argument."""
import os
from pathlib import Path
import re
import sys

import jpype

game = Path(sys.argv[1]).resolve()
package = Path(__file__).resolve().parents[1]
window = package / 'Contents/mods/auto_weapon_swap/common/media/lua/client/AutoWeaponSwap/Window.lua'
source = window.read_text(encoding='utf-8')
fit = re.search(r'(local function fitName\(.*?\nend)\n\nfunction Window:new', source, re.S).group(1)
os.chdir(game)  # J2SEPlatform loads stdlib.lua from the working directory
jpype.startJVM(str(game / 'jre64/bin/server/jvm.dll'),
              '--enable-native-access=ALL-UNNAMED', classpath=[str(game / 'projectzomboid.jar')])
platform = jpype.JClass('se.krka.kahlua.j2se.J2SEPlatform').getInstance()
environment = platform.newEnvironment()
# Translations arrive as Java strings
for key, value in {
    'russian': 'Очень длинное русское название оружия',
    'shortRussian': 'Топор', 'mixed': 'Русский Steel топор',
    'japanese': '日本語の長い武器名',
}.items():
    environment.rawset(key, jpype.JString(value))
thread = jpype.JClass('se.krka.kahlua.vm.KahluaThread')(platform, environment)
thread.debugOwnerThread = jpype.JClass('java.lang.Thread').currentThread()
compiler = jpype.JClass('se.krka.kahlua.luaj.compiler.LuaCompiler')
compiler.loadstring(source, str(window), environment)
script = r'''
UIFont = {Small = 1}
local calls = 0
local constant = false
function getTextManager()
    return {MeasureStringX = function(_, _, text)
        calls = calls + 1
        return constant and 1000000 or #text * 8
    end}
end
''' + fit + r'''
-- Kahlua indexes Java characters
assert(#shortRussian == 5)
assert(russian:gsub("[%z\1-\127\194-\244][\128-\191]*$", "") == russian)
for _, name in ipairs({russian, shortRussian, mixed, japanese, "Long English weapon"}) do
    calls = 0
    local result = fitName(name, 64)
    assert(result == name or result:sub(-3) == "...")
    assert(#result * 8 <= 64)
    assert(calls <= #name + 1)
    if result ~= name then assert(result == name:sub(1, 5) .. "...") end
end
assert(fitName(shortRussian, 40) == shortRussian)
assert(fitName("", 0) == "")
assert(fitName(russian, 0) == "...")
assert(fitName(russian, 24) == "...")
constant = true; calls = 0
assert(fitName(russian, 64) == "..." and calls == #russian + 1)
return "Kahlua: Cyrillic regression reproduced; bounded truncation checks passed"
'''
closure = compiler.loadstring(script, 'auto_weapon_swap_label_regression', environment)
result = thread.pcall(closure, jpype.JArray(jpype.JClass('java.lang.Object'))(0))
if not result[0]:
    raise AssertionError('\n'.join(str(value) for value in result))
print(result[1])
