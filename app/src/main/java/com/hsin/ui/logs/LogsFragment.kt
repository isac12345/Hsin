package com.hsin.ui.logs

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.hsin.HsinRepository
import com.hsin.MainActivity
import com.hsin.databinding.FragmentLogsBinding
import kotlinx.coroutines.launch

/** Log modul apa adanya (tidak difilter ulang di app). */
class LogsFragment : Fragment() {

    private var _binding: FragmentLogsBinding? = null
    private val binding get() = _binding!!
    private val repo by lazy { HsinRepository() }
    private var suppressCallback = false

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentLogsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val types = listOf("all", "boot", "apply", "rollback", "error")
        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, types)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spnLogType.adapter = adapter

        binding.spnLogType.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
            override fun onItemSelected(parent: AdapterView<*>?, v: View?, position: Int, id: Long) {
                if (suppressCallback) return
                load(types[position])
            }
        }
        load("all")
    }

    private fun load(type: String) {
        binding.progressBar.visibility = View.VISIBLE
        lifecycleScope.launch {
            try {
                val text = repo.logs(type)
                if (_binding == null) return@launch
                binding.tvLogs.text = text.ifBlank { "(log kosong)" }
            } catch (t: Throwable) {
                (activity as? MainActivity)?.showMessage("Log gagal: ${t.message}")
            } finally {
                _binding?.progressBar?.visibility = View.GONE
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
