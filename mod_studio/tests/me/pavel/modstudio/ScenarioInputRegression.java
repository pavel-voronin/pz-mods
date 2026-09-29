package me.pavel.modstudio;

import java.lang.instrument.Instrumentation;
import java.nio.DoubleBuffer;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.PatchEngine;
import org.lwjgl.glfw.GLFW;
import org.lwjglx.input.Keyboard;
import org.lwjglx.input.Mouse;

/** Applies the real ZombieBuddy advice to deterministic device fixtures, without desktop input. */
public final class ScenarioInputRegression {
    public static void premain(String args,Instrumentation instrumentation)throws Exception {
        var field=Loader.class.getDeclaredField("g_instrumentation");field.setAccessible(true);field.set(null,instrumentation);
    }
    static void check(boolean ok,String message){if(!ok)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception {
        check(GLFW.glfwGetKey(1,87)==1,"unfiltered fixture");
        PatchEngine.applyPatches("me.pavel.modstudio",ScenarioInputRegression.class.getClassLoader());
        check(GLFW.glfwGetKey(1,87)==1,"normal game key passes");
        var claimed=ScenarioHost.class.getDeclaredField("claimed");claimed.setAccessible(true);claimed.setBoolean(null,true);
        for(int key:new int[]{87,256,290,258,342})check(GLFW.glfwGetKey(1,key)==0,"blocked gameplay/debug/Escape key "+key);
        for(int button=0;button<8;button++)check(GLFW.glfwGetMouseButton(1,button)==0,"blocked mouse button");
        Keyboard.addKeyEvent(87,1);Keyboard.addCharEvent('w');Mouse.addMoveEvent(90,80);Mouse.addButtonEvent(0,true);
        check(Keyboard.events==0&&Mouse.events==0,"callbacks discarded");
        Mouse.wheel=5;check(Mouse.getDWheel()==0&&Mouse.wheel==0,"wheel drained");
        double[] x={0},y={0};GLFW.glfwGetCursorPos(1,x,y);check(x[0]==12&&y[0]==13,"first cursor sample");
        GLFW.position=500;GLFW.glfwGetCursorPos(1,x,y);check(x[0]==12&&y[0]==13,"moving cursor frozen");
        var bx=DoubleBuffer.allocate(3);var by=DoubleBuffer.allocate(3);bx.position(1);by.position(2);
        GLFW.glfwGetCursorPos(1,bx,by);check(bx.get(1)==12&&by.get(2)==13&&bx.position()==1&&by.position()==2,"buffer overload shares cursor and preserves position");
        GLFW.glfwGetCursorPos(2,x,(double[])null);check(x[0]==500,"independent window");
        check(GLFW.glfwWindowShouldClose(1)&&GLFW.glfwGetWindowAttrib(1,0)==0,"close and focus unchanged");
        // Host finish keeps filtering during artifact flush and process shutdown.
        ScenarioHost.finish("failed","test");check(GLFW.glfwGetKey(1,87)==0,"cleanup still protected");
        claimed.setBoolean(null,false);
        check(GLFW.glfwGetKey(1,87)==1&&GLFW.glfwGetMouseButton(1,0)==1,"unclaimed process passes input");
        GLFW.glfwGetCursorPos(1,x,y);check(x[0]==500,"normal cursor restored");
        Keyboard.addKeyEvent(87,1);Keyboard.addCharEvent('w');Mouse.addMoveEvent(90,80);Mouse.addButtonEvent(0,true);
        check(Keyboard.events==2&&Mouse.events==2,"normal callbacks pass");
        Mouse.wheel=3;check(Mouse.getDWheel()==3,"normal wheel passes");
        System.out.println("PASS: transformed device polling, both cursor overloads, callbacks, wheel, normal session, cleanup, focus and close.");
    }
}
