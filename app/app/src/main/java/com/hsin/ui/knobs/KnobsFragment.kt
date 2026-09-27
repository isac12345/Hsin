package com.hsin.ui.knobs

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.hsin.HsinRepository
import com.hsin.databinding.FragmentKnobsBinding
import com.hsin.model.KnobsResponse
import kotlinx.coroutines.launch

/**
 * Layar Knobs: semua pilihan yang benar-benar bisa ditulis modul, diambil
 * dari `action.sh knobs` (tidak ada angka tuning yang di-hardcode di app).
 * User memilih dulu, lalu satu tombol Apply mengirim semuanya sekaligus.
 */
class KnobsFragment : Fragment() {

    private var _binding: FragmentKnobsBinding? = null
    private val binding get() = _binding!!
    private val repo by lazy { HsinRepository() }
    private val controller by lazy { ApplyController(repo) }

    private var knobs: KnobsResponse? = null
    private var profile: String = "balanced"

    // Draft: key modul -> nilai yang dipilih user.
    private val knobDraft = mutableMapOf<String, String>()
    private val configDraft = mutableMapOf<String, String>()
    // Simpan state toggle agar tidak ter-reset tiap recycle.
    private val toggleState = mutableMapOf<String, Boolean>()

    private lateinit var adapter: KnobsAdapter

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentKnobsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        adapter = KnobsAdapter(::onChoice, ::onToggle)
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
        binding.btnApply.setOnClickListener { applyNow() }
        binding.swipeRefresh.setOnRefreshListener { load() }
        load()
    }

    private fun load() {
        binding.swipeRefresh.isRefreshing = true
        binding.btnApply.isEnabled = false
        lifecycleScope.launch {
            try {
                val r = repo.knobs()
                knobs = r
                profile = r.profiles.firstOrNull { it == "balanced" } ?: r.profiles.firstOrNull() ?: "balanced"
                render()
            } catch (t: Throwable) {
                toast("Gagal baca knob: ${t.message}")
            } finally {
                binding.swipeRefresh.isRefreshing = false
            }
        }
    }

    private fun render() {
        val r = knobs ?: return
        val rows = KnobsRowBuilder.build(r)
        adapter.submit(rows)
        binding.btnApply.isEnabled = true
        binding.btnApply.text = "Apply ($profile)"
    }

    private fun onChoice(row: KnobRow.Choice, value: String) {
        if (!row.enabled) return
        if (row.id == "PROFILE") {
            profile = value
            binding.btnApply.text = "Apply ($profile)"
            return
        }
        when (row.sink) {
            KnobRow.Sink.KNOB -> knobDraft[row.id] = value
            KnobRow.Sink.CONFIG -> configDraft[row.id] = value
        }
    }

    private fun onToggle(row: KnobRow.Toggle, checked: Boolean) {
        if (!row.enabled) return
        toggleState[row.id] = checked
        configDraft[row.id] = checked.toString()
    }

    private fun applyNow() {
        val configs = configDraft.toMutableMap()
        val r = knobs
        if (r != null && toggleState["ALLOW_EXTREME"] == true) configs["ALLOW_EXTREME"] = "true"

        binding.btnApply.isEnabled = false
        binding.progressBar.visibility = View.VISIBLE
        lifecycleScope.launch {
            try {
                val result = controller.apply(profile, knobDraft.toMap(), configs)
                if (result.isSuccess) {
                    toast("Apply ${profile} selesai (${result.applied.size} tweak)")
                    knobDraft.clear()
                    configDraft.clear()
                    load()
                } else {
                    val first = result.failures.first()
                    toast("Gagal ${result.failures.size}: ${first.first} (${first.second.take(80)})")
                }
            } catch (t: Throwable) {
                toast("Apply gagal: ${t.message}")
            } finally {
                binding.progressBar.visibility = View.GONE
                binding.btnApply.isEnabled = true
            }
        }
    }

    private fun toast(msg: String) {
        if (isAdded) Toast.makeText(requireContext(), msg, Toast.LENGTH_LONG).show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
