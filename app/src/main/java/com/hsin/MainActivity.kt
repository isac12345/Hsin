package com.hsin

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.setupWithNavController
import com.hsin.databinding.ActivityMainBinding

/**
 * Satu activity, tiga tab (Status / Knobs / Logs). App sengaja tidak
 * menjadi pemilik logika tuning: semua keputusan user disimpan dan
 * dijalankan oleh modul HSIN lewat HsinRepository.
 */
class MainActivity : AppCompatActivity() {

    private val viewModel: MainViewModel by viewModels()
    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        val navHost = supportFragmentManager
            .findFragmentById(R.id.nav_host_fragment) as NavHostFragment
        binding.bottomNav.setupWithNavController(navHost.navController)

        viewModel.messages.observe(this) { msg ->
            if (!msg.isNullOrBlank()) {
                com.google.android.material.snackbar.Snackbar
                    .make(binding.root, msg, com.google.android.material.snackbar.Snackbar.LENGTH_LONG)
                    .show()
                viewModel.clearMessage()
            }
        }
    }

    /** Dipanggil fragment untuk menampilkan pesan tanpa Coupling ke LiveData. */
    fun showMessage(text: String) {
        viewModel.postMessage(text)
    }
}
