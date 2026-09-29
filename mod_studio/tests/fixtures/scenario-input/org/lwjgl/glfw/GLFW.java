package org.lwjgl.glfw;
import java.nio.DoubleBuffer;
/** Device boundary fixture: deliberately reports held keys/buttons and moving cursor. */
public final class GLFW {
    public static double position=12;
    public static int glfwGetKey(long window,int key){return 1;}
    public static int glfwGetMouseButton(long window,int button){return 1;}
    public static void glfwGetCursorPos(long window,double[] x,double[] y){if(x!=null)x[0]=position;if(y!=null)y[0]=position+1;}
    public static void glfwGetCursorPos(long window,DoubleBuffer x,DoubleBuffer y){if(x!=null)x.put(x.position(),position);if(y!=null)y.put(y.position(),position+1);}
    public static boolean glfwWindowShouldClose(long window){return true;}
    public static int glfwGetWindowAttrib(long window,int attribute){return 0;}
}
