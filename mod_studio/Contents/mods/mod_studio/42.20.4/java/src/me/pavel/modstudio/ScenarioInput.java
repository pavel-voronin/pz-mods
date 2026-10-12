package me.pavel.modstudio;

import java.nio.DoubleBuffer;
import java.util.HashMap;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Patch;

/** Process-local device filter. OS shortcuts, focus and window close remain native. */
public final class ScenarioInput {
    private static final Map<Long,double[]> cursors=new HashMap<>();
    public static boolean blocked(){return ScenarioHost.suppressInput();}
    // GLFW F12: keep the native screenshot shortcut available during scenarios.
    public static boolean blockedKey(int key){return key!=301&&blocked();}
    public static synchronized void cursor(long window,double[] x,double[] y){
        if(!blocked()){cursors.remove(window);return;}
        double[] fixed=cursors.computeIfAbsent(window,k->new double[]{Double.NaN,Double.NaN});
        if(x!=null&&x.length>0){if(Double.isNaN(fixed[0]))fixed[0]=x[0];x[0]=fixed[0];}
        if(y!=null&&y.length>0){if(Double.isNaN(fixed[1]))fixed[1]=y[0];y[0]=fixed[1];}
    }
    public static synchronized void cursor(long window,DoubleBuffer x,DoubleBuffer y){
        if(!blocked()){cursors.remove(window);return;}
        double[] fixed=cursors.computeIfAbsent(window,k->new double[]{Double.NaN,Double.NaN});
        if(x!=null&&x.hasRemaining()){int p=x.position();if(Double.isNaN(fixed[0]))fixed[0]=x.get(p);x.put(p,fixed[0]);}
        if(y!=null&&y.hasRemaining()){int p=y.position();if(Double.isNaN(fixed[1]))fixed[1]=y.get(p);y.put(p,fixed[1]);}
    }
    @Patch(className="org.lwjgl.glfw.GLFW",methodName="glfwGetKey",warmUp=true)
    public static class Keys {
        @Patch.OnExit public static void exit(@Patch.Argument(1) int key,@Patch.Return(readOnly=false) int value){if(ScenarioInput.blockedKey(key))value=0;}
    }
    @Patch(className="org.lwjgl.glfw.GLFW",methodName="glfwGetMouseButton",warmUp=true)
    public static class Buttons {
        @Patch.OnExit public static void exit(@Patch.Return(readOnly=false) int value){if(ScenarioInput.blocked())value=0;}
    }
    @Patch(className="org.lwjgl.glfw.GLFW",methodName="glfwGetCursorPos",warmUp=true,strictMatch=true)
    public static class Cursor {
        // Object binds both overloads; ZombieBuddy's array argument matcher strips
        // the component type and cannot match an annotated double[] parameter.
        @Patch.OnExit public static void exit(@Patch.Argument(0) long window,@Patch.Argument(1) Object x,@Patch.Argument(2) Object y){
            if(ScenarioInput.blocked()){
                if(x instanceof DoubleBuffer||y instanceof DoubleBuffer)ScenarioInput.cursor(window,(DoubleBuffer)x,(DoubleBuffer)y);
                else ScenarioInput.cursor(window,(double[])x,(double[])y);
            }
        }
    }
    @Patch(className="org.lwjglx.input.Keyboard",methodName="addKeyEvent",warmUp=true)
    public static class KeyEvents {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) int key){return ScenarioInput.blockedKey(key);}
    }
    @Patch(className="org.lwjglx.input.Keyboard",methodName="addCharEvent",warmUp=true)
    public static class TextEvents {
        @Patch.OnEnter(skipOn=true) public static boolean enter(){return ScenarioInput.blocked();}
    }
    @Patch(className="org.lwjglx.input.Mouse",methodName="addMoveEvent",warmUp=true)
    public static class MoveEvents {
        @Patch.OnEnter(skipOn=true) public static boolean enter(){return ScenarioInput.blocked();}
    }
    @Patch(className="org.lwjglx.input.Mouse",methodName="addButtonEvent",warmUp=true)
    public static class ButtonEvents {
        @Patch.OnEnter(skipOn=true) public static boolean enter(){return ScenarioInput.blocked();}
    }
    @Patch(className="org.lwjglx.input.Mouse",methodName="getDWheel",warmUp=true)
    public static class Wheel {
        // Drain the wheel even while suppressed; never replay accumulated scrolling.
        @Patch.OnExit public static void exit(@Patch.Return(readOnly=false) int value){if(ScenarioInput.blocked())value=0;}
    }
}
