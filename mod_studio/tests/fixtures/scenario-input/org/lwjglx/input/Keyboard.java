package org.lwjglx.input;
public final class Keyboard {
    public static int events;
    public static void addKeyEvent(int key,int status){events++;}
    public static void addCharEvent(char c){events++;}
}
