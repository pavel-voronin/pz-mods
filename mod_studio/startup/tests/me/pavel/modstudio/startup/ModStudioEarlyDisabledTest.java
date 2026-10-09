package me.pavel.modstudio.startup;
public final class ModStudioEarlyDisabledTest {
    public static void main(String[] arguments){
        if(StartupScanner.enabled || StartupWatch.enabled || StartupTrace.active)throw new AssertionError("Disabled or incompatible early preparation is active");
        System.out.println("Production early fallback PASS: native startup retained");
    }
}
