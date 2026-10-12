package org.lwjgl.opengl;
/** Fail safely before native GL calls to exercise user-capture error isolation. */
public final class GL11 {
    public static final int GL_READ_BUFFER=0x0c02,GL_PACK_ALIGNMENT=0x0d05;
    public static int glGetInteger(int value){throw new IllegalStateException("fixture has no GL context");}
    public static void glReadBuffer(int value){}
    public static void glPixelStorei(int name,int value){}
}
