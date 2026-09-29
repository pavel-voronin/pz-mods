package org.lwjglx.input;
public final class Mouse {
    public static int events,wheel;
    public static void addMoveEvent(double x,double y){events++;}
    public static void addButtonEvent(int button,boolean pressed){events++;}
    public static int getDWheel(){int value=wheel;wheel=0;return value;}
}
