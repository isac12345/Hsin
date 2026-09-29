package com.hsin

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.hsin.ui.HsinApp
import com.hsin.ui.theme.HsinTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HsinTheme {
                HsinApp()
            }
        }
    }
}
