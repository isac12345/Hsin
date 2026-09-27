package com.hsin;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.widget.Toast;
import java.util.function.Consumer;

public class HsinCompat {

    public static boolean isAtLeast(int api) {
        return android.os.Build.VERSION.SDK_INT >= api;
    }

    public static void safeSnackbarMessage(View view, String msg) {
        if (view == null || msg == null || msg.isEmpty()) {
            return;
        }
        try {
            com.google.android.material.snackbar.Snackbar
                .make(view, msg, com.google.android.material.snackbar.Snackbar.LENGTH_LONG)
                .show();
        } catch (Exception e) {
            Log.w("HSIN", "safeSnackbarMessage failed", e);
        }
    }

    public static void installCrashGuard(final Context ctx, final Consumer<String> consumer) {
        if (ctx == null) {
            return;
        }
        final Thread.UncaughtExceptionHandler old = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            final String msg = "HSIN menemui galat, kembali aman";
            try {
                Log.e("HSIN", msg, throwable);
            } catch (Exception ignored) {}
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show();
                } catch (Exception ignored) {}
                if (consumer != null) {
                    try {
                        consumer.accept(msg);
                    } catch (Exception ignored) {}
                }
            });
            if (old != null) {
                try {
                    old.uncaughtException(thread, throwable);
                } catch (Exception ignored) {}
            }
        });
    }
}
