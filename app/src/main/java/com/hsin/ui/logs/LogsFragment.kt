package com.hsin.ui.logs

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Spinner
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModels
import com.hsin.HsinRepository
import com.hsin.MainViewModel
import com.hsin.databinding.FragmentLogsBinding
import kotlinx.coroutines.launch

class LogsFragment : Fragment() {
    private val viewModel: MainViewModel by viewModels()
    private val repo = HsinRepository()
    private var _binding: FragmentLogsBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentLogsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        ArrayAdapter.createFromResource(
            requireContext(),
            arrayOf("boot", "apply", "rollback", "error", "all"),
            android.R.layout.simple_spinner_item
        ).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); binding.spnLogType.adapter = it }
        binding.spnLogType.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(p0: android.widget.AdapterView?) {}
            override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                loadLogs(binding.spnLogType.getItemAtPosition(pos).toString())
            }
        }
        loadLogs("all")
    }

    private fun loadLogs(type: String) {
        binding.progressBar.visibility = View.VISIBLE
        binding.tvLogs.text = ""
        lifecycleScope.launch {
            try {
                val logs = HsinRepository().logs(type)
                binding.tvLogs.text = logs
            } catch (e: Exception) {
                binding.tvLogs.text = "Error: ${e.message}"
            } finally {
                binding.progressBar.visibility = View.GONE
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}