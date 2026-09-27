package com.hsin.ui.status

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModels
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.hsin.MainViewModel
import com.hsin.HsinRepository
import com.hsin.databinding.FragmentStatusBinding
import kotlinx.coroutines.launch

class StatusFragment : Fragment() {
    private val viewModel: MainViewModel by viewModels()
    private val repo = HsinRepository()
    private var _binding: FragmentStatusBinding? = null
    private val binding get() = _binding!!

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
                val status = HsinRepository().status()
                val device = HsinRepository().device()
                binding.apply {
                    tvCpuTemp.text = "${status.cpu_temp / 1000}°C"
                    tvGpuTemp.text = "${status.gpu_temp / 1000}°C"
                    tvCpuFreq.text = "${status.cpu_freq / 1000} MHz"
                    tvCpuFreqBig.text = "${status.cpu_freq_big / 1000} MHz"
                    tvCpuFreqLittle.text = "${status.cpu_freq_little / 1000} MHz"
                    tvGpuFreq.text = "${status.gpu_freq / 1000} MHz"
                    tvRamUsed.text = "${status.ram_used_kb / 1024} MB"
                    tvRamTotal.text = "${status.ram_total_kb / 1024} MB"
                    tvBattery.text = "${status.battery_pct}% (${status.battery_status})"
                    tvBatteryTemp.text = "${status.battery_temp_c}°C"
                    tvRefreshHz.text = "${status.refresh_hz} Hz"
                    tvGameFps.text = "${status.game_fps} FPS"
                    tvUptime.text = formatUptime(status.uptime_sec)
                    tvProfile.text = status.profile
                    tvApplyStatus.text = status.apply_status
                    tvCpuLoad.text = "${status.cpu_load_x100 / 100}.${status.cpu_load_x100 % 100}%"
                    tvZramPct.text = "${status.zram_pct}%"
                    tvGlobalRr.text = "${status.global_rr_enabled}/${status.global_rr_reduced} ${status.global_rr_peak_hz}/${status.global_rr_min_hz}Hz"
                    tvDvfs.text = "${status.dvfs_enabled} CPU:${status.dvfs_cpu_limit}% GPU:${status.dvfs_gpu_limit}%"
                    tvFrameLimit.text = status.frame_limit_disabled
                    tvSf.text = status.surfaceflinger_enabled
                    tvDeviceSoc.text = device.soc
                    tvDeviceGpu.text = device.gpu
                    tvDeviceKernel.text = device.kernel
                    tvDeviceRam.text = "${device.ram_kb} kB"
                    tvDeviceId.text = device.device_id
                }
            } catch (e: Exception) {
                (activity as? MainActivity)?.let { it.mainViewModel.reportError("Status error: ${e.message}") }
            } finally {
                binding.swipeRefresh.isRefreshing = false
            }
        }
    }

    private fun formatUptime(seconds: Long): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return "${h}h ${m}m ${s}s"
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}