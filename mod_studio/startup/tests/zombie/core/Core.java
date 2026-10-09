package zombie.core;

/** Isolated instrumentation fixture. No native libraries, window or game loop. */
public final class Core {
    private static final Core instance=new Core();
    public static final Thread caller=Thread.currentThread();
    public int polls;
    public static Core getInstance(){return instance;}
    public void DoFrameReady(){
        if(Thread.currentThread()!=caller)throw new AssertionError("Frame polling left the caller thread");
        polls++;
    }
}
