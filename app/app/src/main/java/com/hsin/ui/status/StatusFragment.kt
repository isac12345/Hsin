package com.hsin.ui.status

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.hsin.HsinRepository
import com.hsin.MainActivity
import com.hsin.databinding.FragmentStatusBinding
import kotlinx.coroutines.launch

/**
 * Status langsung: device + angka runtime. Semua angka datang dari
 * `action.sh status` / `action.sh device`, tidak ada yang ditebak di app.
 */
class StatusFragment : Fragment() {

    private var _binding: FragmentStatusBinding? = null
    private val binding get() = _binding!!
    private val repo by lazy { HsinRepository() }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentStatusBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.swipeRefresh.setOnRefreshListener { refresh() }
        refresh()
    }

    private fun refresh() {
        binding.swipeRefresh.isRefreshing = true
        lifecycleScope.launch {
            try {
                val s = repo.status()
                val d = repo.device()
                if (_binding == null) return@launch
                with(binding) {
                    tvDeviceSoc.text = "SoC: ${d.soc.ifBlank { "?" }}"
                    tvDeviceGpu.text = "GPU: ${d.gpu.ifBlank { "?" }}"
                    tvDeviceKernel.text = "Kernel: ${d.kernel.ifBlank { "?" }}"
                    tvDeviceRam.text = "RAM: ${d.ramKb.ifBlank { "?" }} kB"
                    tvDeviceId.text = "ID: ${d.deviceId.ifBlank { "?" }}"

                    tvCpuTemp.text = "CPU: ${s.cpuTemp / 1000}°C"
                    tvGpuTemp.text = "GPU: ${s.gpuTemp / 1000}°C"
                    tvCpuFreq.text = "CPU now: ${s.cpuFreq / 1000} MHz (plafon ${s.cpuMaxKhz / 1000} MHz)"
                    tvCpuFreqBig.text = "Big: ${s.cpuFreqBig / 1000} MHz"
                    tvCpuFreqLittle.text = "Little: ${s.cpuFreqLittle / 1000} MHz"
                    tvGpuFreq.text = "GPU: ${s.gpuFreq / 1000} MHz (plafon ${s.gpuMaxKhz / 1000} MHz)"
                    tvRamUsed.text = "RAM: ${s.ramUsedKb / 1024} MB / ${s.ramTotalKb / 1024} MB"
                    tvBattery.text = "Baterai: ${s.batteryPct}% (${s.batteryStatus})"
                    tvBatteryTemp.text = "Baterai suhu: ${s.batteryTempC}°C"
                    tvRefreshHz.text = "Refresh: ${s.refreshHz} Hz"
                    tvGameFps.text = "Game FPS: ${s.gameFps}"
                    tvUptime.text = "Uptime: ${formatUptime(s.uptimeSec)}"
                    tvProfile.text = "Profil: ${s.profile}"
                    tvApplyStatus.text = "Apply: ${s.applyStatus}"
                    tvCpuLoad.text = "Beban CPU: ${s.cpuLoadX100 / 100}.${(s.cpuLoadX100 % 100).toString().padStart(2, '0')}"
                    tvZramPct.text = "zRAM terpakai: ${s.zramPct}%"
                    tvDvfsLimit.text = "Batas DVFS: CPU ${s.dvfsCpuLimit}% / GPU ${s.dvfsGpuLimit}%"
                }
            } catch (t: Throwable) {
                (activity as? MainActivity)?.showMessage("Status gagal: ${t.message}")
            } finally {
                _binding?.swipeRefresh?.isRefreshing = false
            }
        }
    }

    private fun formatUptime(seconds: Long): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return "${h}j ${m}m ${s}d"
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
