package zombie.core.opengl;
/** Deterministic render queue; no GL context is created by this input test. */
public final class RenderThread {
    public static final java.util.ArrayDeque<Runnable> queued=new java.util.ArrayDeque<>();
    public static void queueInvokeOnRenderContext(Runnable task){queued.add(task);}
    public static void invokeOnRenderContext(Runnable task){task.run();}
}
