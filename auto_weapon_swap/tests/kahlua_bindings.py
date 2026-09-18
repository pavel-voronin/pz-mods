"""Exercise production input polling with Kahlua and the installed game's key map."""
import os
from pathlib import Path
import sys
import jpype

game = Path(sys.argv[1]).resolve()
source = (Path(__file__).resolve().parents[1] / 'Contents/mods/auto_weapon_swap/common/media/lua/client/AutoWeaponSwap/Options.lua').read_text()
os.chdir(game)
jpype.startJVM(str(game / 'jre64/bin/server/jvm.dll'), '--enable-native-access=ALL-UNNAMED',
              classpath=[str(p) for p in game.glob('*.jar')])
J = jpype.JClass
core = J('zombie.core.Core').getInstance()
keyboard = J('zombie.input.GameKeyboard')
mouse = J('zombie.input.Mouse')

def keyboard_array(name):
    field = keyboard.class_.getDeclaredField(name)
    field.setAccessible(True)
    value = jpype.JArray(jpype.JBoolean)(512)
    field.set(None, value)
    return value

down = keyboard_array('down')
keyboard_array('lastDown')
keyboard_array('eatKey')
mouse.buttonDownStates = jpype.JArray(jpype.JBoolean)(8)
mouse.buttonPrevStates = jpype.JArray(jpype.JBoolean)(8)
mouse.uiCaptured = jpype.JArray(jpype.JBoolean)(8)
platform = J('se.krka.kahlua.j2se.J2SEPlatform').getInstance()
env = platform.newEnvironment()
manager = J('se.krka.kahlua.converter.KahluaConverterManager')()
# Convert Lua numbers to Java ints for the standalone exposer
converter = jpype.JProxy('se.krka.kahlua.converter.LuaToJavaConverter', dict={
    'getLuaType': lambda: J('java.lang.Double').class_,
    'getJavaType': lambda: J('java.lang.Integer').class_,
    'fromLuaToJava': lambda value, cls: J('java.lang.Integer')(int(value))})
manager.addLuaConverter(converter)
exposer = J('se.krka.kahlua.integration.expose.LuaJavaClassExposer')(manager, platform, env)
for method in keyboard.class_.getMethods():
    if method.getName() == 'isKeyDown' and str(method.getParameterTypes()[0]) == 'class java.lang.String':
        exposer.exposeGlobalClassFunction(env, keyboard.class_, method, 'nativeDown')
for method in keyboard.class_.getMethods():
    if method.getName() == 'isKeyDownRaw':
        exposer.exposeGlobalClassFunction(env, keyboard.class_, method, 'nativeRawDown')
for method in mouse.class_.getMethods():
    if method.getName() == 'isButtonDown':
        exposer.exposeGlobalClassFunction(env, mouse.class_, method, 'nativeMouseDown')
for method in core.getClass().getMethods():
    if method.getName() == 'addKeyBinding' and len(method.getParameterTypes()) == 6:
        exposer.exposeGlobalObjectFunction(env, core, method, 'nativeAdd')
thread = J('se.krka.kahlua.vm.KahluaThread')(platform, env)
thread.debugOwnerThread = J('java.lang.Thread').currentThread()
J('zombie.Lua.LuaManager').thread = thread
compiler = J('se.krka.kahlua.luaj.compiler.LuaCompiler')

def run(script):
    result = thread.pcall(compiler.loadstring(script, 'keybind_test', env), jpype.JArray(J('java.lang.Object'))(0))
    assert result[0], '\n'.join(str(value) for value in result)

run(r'''
function require() end
function getText(key) return key end
function getKeyName(key) return tostring(key) end
local assignedKey = 0
MainOptions = {}
GameKeyboard = {isKeyDown = function(name) return not typing and nativeDown(name) end,
    isKeyDownRaw = nativeRawDown}
Mouse = {BTN_OFFSET = 10000, isButtonDown = nativeMouseDown}
local core = {getKey = function() return assignedKey end, getAltKey = function() return 0 end,
    isDoingTextEntry = function() return typing end}
function assign(key, shift, ctrl, alt)
    assignedKey = key
    nativeAdd("AWSOpenExclusions", key, 0, shift, ctrl, alt)
end
function getCore() return core end
function isGamePaused() return paused end
function getSpecificPlayer() return {isDead = function() return dead end} end
AutoWeaponSwap = {toggleExclusions = function() toggles = toggles + 1 end}
Events = {OnTickEvenPaused={Add=function() end}}
toggles = 0
''' + source)

def tick(expected):
    run('AutoWeaponSwap.onMenuInput(); assert(toggles == %d)' % expected)

# Ctrl+K, with either Ctrl key and no repeat while held
run('assign(37, false, true, false)')
down[37] = True
tick(0)
down[29] = True
tick(1)
for _ in range(4): tick(1)
down[29] = False; tick(1)
down[29] = True; tick(1)
down[37] = down[29] = False
tick(1)
down[37] = down[157] = True
tick(2)
down[37] = down[157] = False
tick(2)
expected = 2
for flags, modifier in [('true,false,false', 42), ('false,false,true', 56), ('false,false,false', None)]:
    run('assign(37,' + flags + ')')
    down[37] = True
    if modifier is not None:
        tick(expected)
        down[modifier] = True
    expected += 1
    tick(expected); tick(expected)
    down[37] = False
    if modifier is not None: down[modifier] = False
    tick(expected)
# Mouse buttons, including the right-click delay
for button in [0, 2, 3, 4, 1]:
    run('assign(%d,false,false,false)' % (10000 + button))
    mouse.buttonDownStates[button] = True
    if button == 1:
        delay = mouse.class_.getDeclaredField('timeRightPressed')
        delay.setAccessible(True); delay.setFloat(None, 0.0)
        tick(expected)
        delay.setFloat(None, 0.2)
    expected += 1
    tick(expected); tick(expected)
    mouse.buttonDownStates[button] = False
    tick(expected)
run('assign(10002,false,false,false)')
mouse.buttonDownStates[2] = True; mouse.uiCaptured[2] = True
tick(expected)
mouse.buttonDownStates[2] = False; tick(expected)
for guard in ['typing', 'paused', 'dead']:
    run(guard + '=true')
    mouse.buttonDownStates[2] = True; tick(expected)
    run(guard + '=false')
    tick(expected)  # No activation on leaving the blocked state
    mouse.buttonDownStates[2] = False; tick(expected)
run('MainOptions.instance={isVisible=function() return true end}')
mouse.buttonDownStates[2] = True; tick(expected)
run('MainOptions.instance=nil')
tick(expected)
mouse.buttonDownStates[2] = False; tick(expected)
run('assign(37,false,false,false)')
for guard in ['typing', 'paused', 'dead']:
    run(guard + '=true')
    down[37] = True; tick(expected)
    run(guard + '=false')
    tick(expected)
    down[37] = False; tick(expected)
    down[37] = True; expected += 1; tick(expected)
    down[37] = False; tick(expected)
for blocked in ['MainScreen.instance', 'MainOptions.instance', 'MainOptions.setKeybindDialog']:
    run('MainScreen = {}; ' + blocked + '={isVisible=function() return true end}')
    down[37] = True; tick(expected)
    run(blocked + '=nil'); tick(expected)
    down[37] = False; tick(expected)
    down[37] = True; expected += 1; tick(expected)
    down[37] = False; tick(expected)
run('assign(0,false,true,false)')
mouse.buttonDownStates[2] = True; down[37] = True; down[29] = True
tick(expected)
print('Kahlua/native Core + GameKeyboard: modifiers, mouse, hold, UI capture, guards and unassigned passed')
