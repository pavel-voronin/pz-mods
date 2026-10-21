package me.pavel.modstudio;

import java.util.ArrayList;
import java.util.List;

/** One screen session; never persisted to disk. */
final class Selection {
    static final int TITLE = 1, DESCRIPTION = 2, PREVIEW = 4, TAGS = 8, VISIBILITY = 16;
    static final int ALL = 31;
    final String initialId;
    int keepMask;
    boolean armed;
    String error;
    final List<String> events = new ArrayList<>();

    Selection(String initialId) {
        this.initialId = initialId;
        keepMask = initialId == null ? 0 : ALL;
    }

    boolean keep(int field) { return initialId != null && (keepMask & field) != 0; }

    void configure(int mask) {
        keepMask = initialId == null ? 0 : mask & ALL;
        armed = false;
    }
}
