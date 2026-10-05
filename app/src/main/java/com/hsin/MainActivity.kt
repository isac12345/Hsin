package com.hsin

import android.graphics.Color as AColor
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    private val vm: HsinVm by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { HsinApp(vm) }
    }

    override fun onStart() {
        super.onStart()
        vm.onForeground(true)
    }

    override fun onStop() {
        super.onStop()
        vm.onForeground(false)
    }
}

@Composable
fun HsinApp(vm: HsinVm) {
    val pal = Pal(vm.theme, vm.cardAlpha)
    val dark = pal.dark
    val act = LocalContext.current as ComponentActivity

    LaunchedEffect(dark) {
        val style = if (dark) SystemBarStyle.dark(AColor.TRANSPARENT)
        else SystemBarStyle.light(AColor.TRANSPARENT, AColor.TRANSPARENT)
        act.enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
    }

    val scheme = if (dark) darkColorScheme(surface = pal.bg, onSurface = pal.text, background = pal.bg, onBackground = pal.text)
    else lightColorScheme(surface = pal.bg, onSurface = pal.text, background = pal.bg, onBackground = pal.text)

    CompositionLocalProvider(LocalPal provides pal) {
        MaterialTheme(colorScheme = scheme) {
            Box(Modifier.fillMaxSize().background(pal.bg)) {
                val wall = vm.wallBmp
                if (wall != null && (vm.wallCustom || vm.theme == 0)) {
                    Image(bitmap = wall, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    Box(Modifier.fillMaxSize().background(pal.scrim))
                }
                if (vm.customOpen) {
                    CustomScreen(vm)
                } else {
                    when (vm.tab) {
                        0 -> DashScreen(vm)
                        1 -> KnobScreen(vm)
                        2 -> GamesScreen(vm)
                        else -> MonitorScreen(vm)
                    }
                    BottomNav(vm, Modifier.align(Alignment.BottomCenter).navigationBarsPadding())
                    MessageBar(vm, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 84.dp))
                }
                FailureDialog(vm)
            }
        }
    }
}
