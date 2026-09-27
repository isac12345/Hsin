package com.hsin.ui.knobs

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModels
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.hsin.HsinRepository
import com.hsin.MainViewModel
import com.hsin.databinding.FragmentKnobsBinding
import com.hsin.model.CpuPolicyKnob
import com.hsin.model.KnobsResponse
import kotlinx.coroutines.launch
import java.util.HashMap

class KnobsFragment : Fragment() {
    private val viewModel: MainViewModel by viewModels()
    private val repo = HsinRepository()
    private var _binding: FragmentKnobsBinding? = null
    private val binding get() = _binding!!
    private val draft = HashMap<String, Any>()
    private var knobs: KnobsResponse? = null
    private lateinit var adapter: KnobsAdapter

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentKnobsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        adapter = KnobsAdapter(draft, ::onDraftChange)
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
        binding.btnApply.setOnClickListener { applyDraft() }
        loadKnobs()
    }

    private fun loadKnobs() {
        binding.progressBar.visibility = View.VISIBLE
        binding.btnApply.isEnabled = false
        lifecycleScope.launch {
            try {
                val response = repo.knobs()
                knobs = response
                adapter.submitList(response)
                binding.btnApply.isEnabled = true
            } catch (e: Exception) {
                Toast.makeText(requireContext(), "Failed to load knobs: ${e.message}", Toast.LENGTH_LONG).show()
            } finally {
                binding.progressBar.visibility = View.GONE
            }
        }
    }

    private fun onDraftChange(key: String, value: Any) {
        draft[key] = value
    }

    private fun applyDraft() {
        binding.btnApply.isEnabled = false
        binding.progressBar.visibility = View.VISIBLE
        lifecycleScope.launch {
            var success = true
            var lastMsg = ""
            try {
                // Apply config-set for each draft entry
                for ((key, value) in draft) {
                    val result = HsinRepository().configSet(key, value.toString())
                    if (!result.success) {
                        success = false
                        lastMsg = "Failed $key: ${result.message}"
                        break
                    }
                }
                // Then apply profile
                if (success) {
                    val profile = "balanced" // TODO: let user pick profile
                    val applyResult = HsinRepository().apply(profile)
                    if (!applyResult.success) {
                        success = false
                        lastMsg = "Apply failed: ${applyResult.message}"
                    }
                }
            } catch (e: Exception) {
                success = false
                lastMsg = e.message ?: "Unknown error"
            } finally {
                binding.progressBar.visibility = View.GONE
                binding.btnApply.isEnabled = true
                if (success) {
                    Toast.makeText(requireContext(), "Applied successfully", Toast.LENGTH_SHORT).show()
                    draft.clear()
                } else {
                    Toast.makeText(requireContext(), "Apply failed: $lastMsg", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}