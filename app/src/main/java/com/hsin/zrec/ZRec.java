package com.hsin.zrec;

import android.content.Context;
import android.content.Intent;

/** Pintu masuk publik untuk mesin rekam "Suara" (MediaProjection + audio internal/mic) yang dipinjam dari app Zani. */
public final class ZRec {
    private ZRec() { }

    public static final String MIC = ZPrefs.MIC, INT = ZPrefs.INT, CD = ZPrefs.CD, RES = ZPrefs.RES, FPS = ZPrefs.FPS,
            BR = ZPrefs.BR, ORI = ZPrefs.ORI, CODEC = ZPrefs.CODEC, SAFE = ZPrefs.SAFE;

    /** 0 diam, 1 hitung mundur, 2 merekam, 3 jeda, 4 menyimpan. */
    public static int mode() { return State.mode; }

    public static int secs() { return State.secs(); }

    public static void start(Context c) {
        c.startActivity(new Intent(c, CaptureActivity.class).putExtra("mode", "rec").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    public static void shot(Context c) {
        if (State.mode == State.REC || State.mode == State.PAUSE) {
            c.startService(new Intent(c, RecorderService.class).setAction(RecorderService.A_SHOT));
        } else {
            c.startActivity(new Intent(c, CaptureActivity.class).putExtra("mode", "shot").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
    }

    public static void stop(Context c) {
        c.startService(new Intent(c, RecorderService.class).setAction(RecorderService.A_STOP));
    }

    public static void pause(Context c) {
        c.startService(new Intent(c, RecorderService.class).setAction(RecorderService.A_PAUSE));
    }

    public static boolean getB(Context c, String k, boolean d) { return ZPrefs.b(c, k, d); }

    public static int getI(Context c, String k, int d) { return ZPrefs.i(c, k, d); }

    public static void setB(Context c, String k, boolean v) { ZPrefs.put(c, k, v); }

    public static void setI(Context c, String k, int v) { ZPrefs.put(c, k, v); }
}
