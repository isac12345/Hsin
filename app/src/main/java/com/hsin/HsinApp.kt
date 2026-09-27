package com.hsin

import android.app.Application
import kotlinx.coroutines.CoroutineExceptionHandler

class HsinApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Global coroutine exception handler
        Thread.setDefaultUncaughtExceptionHandler { _, throwable ->
            // Log to file or crash reporting
        }
    }
}