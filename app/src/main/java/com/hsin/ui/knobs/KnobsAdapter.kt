package com.hsin.ui.knobs

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.hsin.R
import com.hsin.model.CpuPolicyKnob
import com.hsin.model.GpuNodeKnob
import com.hsin.model.KnobsResponse
import com.hsin.model.IoBlockKnob
import java.util.HashMap

class KnobsAdapter(
    private val draft: HashMap<String, Any>,
    private val onChange: (String, Any) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private var response: KnobsResponse? = null

    sealed class SectionType {
        object CPU : SectionType()
        object GPU : SectionType()
        object MEMORY : SectionType()
        object IO : SectionType()
        object NETWORK : SectionType()
        object DISPLAY : SectionType()
        object FEATURES : SectionType()
    }

    private data class SectionItem(
        val type: SectionType,
        val title: String,
        val items: List<Any> = emptyList()
    )

    private var sections = listOf<SectionItem>()

    fun submitList(response: KnobsResponse) {
        this.response = response
        buildSections(response)
        notifyDataSetChanged()
    }

    private fun buildSections(r: KnobsResponse) {
        val s = mutableListOf<SectionItem>()

        // CPU
        s.add(SectionItem(
            SectionType.CPU, "CPU Policies",
            r.cpu.policies.map { policy ->
                SectionItem(SectionType.CPU, "Policy ${policy.id}", listOf(policy))
            }.flatten()
        ))

        // GPU
        s.add(SectionItem(
            SectionType.GPU, "GPU Nodes",
            r.gpu.nodes.map { node ->
                SectionItem(SectionType.GPU, node.name, listOf(node))
            }.flatten()
        ))

        // Memory
        s.add(SectionItem(SectionType.MEMORY, "Memory", listOf(
            SectionItem(SectionType.MEMORY, "Swappiness", listOf(r.memory.swappiness)),
            SectionItem(SectionType.MEMORY, "ZRAM", listOf(r.memory.zram))
        )))

        // IO
        s.add(SectionItem(SectionType.IO, "I/O Schedulers",
            r.io.blocks.map { block ->
                SectionItem(SectionType.IO, block.name, listOf(block))
            }.flatten()
        ))

        // Network
        s.add(SectionItem(SectionType.NETWORK, "Network", listOf(
            SectionItem(SectionType.NETWORK, "TCP Congestion Control", listOf(r.network.tcp_cc)),
            SectionItem(SectionType.NETWORK, "TCP Fast Open", listOf(r.network.tfo))
        )))

        // Display
        s.add(SectionItem(SectionType.DISPLAY, "Display", listOf(
            SectionItem(SectionType.DISPLAY, "Refresh Rate (Hz)", listOf(r.display.modes_hz)),
            SectionItem(SectionType.DISPLAY, "Renderer", listOf(r.display.renderers)),
            SectionItem(SectionType.DISPLAY, "Downscale %", listOf(r.display.downscale))
        )))

        // Features
        s.add(SectionItem(SectionType.FEATURES, "Features", listOf(
            SectionItem(SectionType.FEATURES, "DVFS Limiter", listOf(r.features.dvfs)),
            SectionItem(SectionType.FEATURES, "Global Refresh Rate", listOf(r.features.global_rr)),
            SectionItem(SectionType.FEATURES, "Frame Limit", listOf(r.features.frame_limit)),
            SectionItem(SectionType.FEATURES, "SurfaceFlinger Tweak", listOf(r.features.surfaceflinger)),
            SectionItem(SectionType.FEATURES, "Gaming Boost", listOf(r.features.gaming)),
            SectionItem(SectionType.FEATURES, "Extreme Opt-in", listOf(r.features.extreme_optin))
        )))

        sections = s
    }

    override fun getItemViewType(position: Int): Int {
        val item = getItem(position)
        return when (item) {
            is SectionItem -> when (item.type) {
                SectionType.CPU -> if (item.items.isEmpty()) 100 else 101
                SectionType.GPU -> if (item.items.isEmpty()) 100 else 102
                SectionType.MEMORY -> if (item.items.isEmpty()) 100 else 103
                SectionType.IO -> if (item.items.isEmpty()) 100 else 104
                SectionType.NETWORK -> if (item.items.isEmpty()) 100 else 105
                SectionType.DISPLAY -> if (item.items.isEmpty()) 100 else 106
                SectionType.FEATURES -> if (item.items.isEmpty()) 100 else 107
            }
            else -> super.getItemViewType(position)
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return when (viewType) {
            100 -> SectionHeaderViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_section_header, parent, false))
            101 -> CpuPolicyViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_knob_spinner, parent, false))
            102 -> GpuNodeViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_knob_spinner, parent, false))
            104 -> IoBlockViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_knob_spinner, parent, false))
            105 -> NetworkViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_knob_spinner, parent, false))
            106 -> DisplayViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_knob_spinner, parent, false))
            107 -> FeatureViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_knob_switch, parent, false))
            else -> super.onCreateViewHolder(parent, viewType)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val item = getItem(position)
        when (holder) {
            is SectionHeaderViewHolder -> holder.bind(item.title)
            is CpuPolicyViewHolder -> holder.bind(item as CpuPolicyKnob)
            is GpuNodeViewHolder -> holder.bind(item as GpuNodeKnob)
            is IoBlockViewHolder -> holder.bind(item as IoBlockKnob)
            is NetworkViewHolder -> holder.bind(item)
            is DisplayViewHolder -> holder.bind(item)
            is FeatureViewHolder -> holder.bind(item)
        }
    }

    private fun getItem(position: Int): Any {
        var count = 0
        for (section in sections) {
            if (position == count) return section
            count++
            for (sub in section.items) {
                count++
                if (position == count) return sub
            }
        }
        return SectionItem(SectionType.FEATURES, "", emptyList())
    }

    override fun getItemCount(): Int {
        var count = 0
        for (section in sections) {
            count++ // header
            count += section.items.size
        }
        return count
    }

    class SectionHeaderViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tv: TextView = view.findViewById(R.id.tvSectionTitle)
        fun bind(title: String) { tv.text = title }
    }

    class CpuPolicyViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tvTitle: TextView = view.findViewById(R.id.tvKnobTitle)
        private val spnGov: Spinner = view.findViewById(R.id.spnGov)
        private val spnFreq: Spinner = view.findViewById(R.id.spnFreq)
        fun bind(p: CpuPolicyKnob) {
            tvTitle.text = "Policy ${p.id} (max ${p.hw_max_khz/1000} MHz)"
            ArrayAdapter.createFromResource(spnGov.context, p.govs.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnGov.adapter = it }
            spnGov.setSelection(p.govs.indexOf(p.cur_gov).coerceAtLeast(0))
            spnGov.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                    onChange("cpu.policy.${p.id}.gov", p.govs[pos])
                }
            }
            if (p.opp_khz.isNotEmpty()) {
                ArrayAdapter.createFromResource(spnFreq.context, p.opp_khz.map { "${it/1000} MHz" }.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnFreq.adapter = it }
                spnFreq.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                    override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                    override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                        onChange("cpu.policy.${p.id}.max_freq", p.opp_khz[pos])
                    }
                }
            } else {
                spnFreq.visibility = View.GONE
            }
        }
    }

    class GpuNodeViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tvTitle: TextView = view.findViewById(R.id.tvKnobTitle)
        private val spnGov: Spinner = view.findViewById(R.id.spnGov)
        private val spnFreq: Spinner = view.findViewById(R.id.spnFreq)
        fun bind(n: GpuNodeKnob) {
            tvTitle.text = n.name
            ArrayAdapter.createFromResource(spnGov.context, n.govs.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnGov.adapter = it }
            spnGov.setSelection(n.govs.indexOf(n.cur_gov).coerceAtLeast(0))
            spnGov.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                    onChange("gpu.node.${n.name}.gov", n.govs[pos])
                }
            }
            if (n.opp_khz.isNotEmpty()) {
                ArrayAdapter.createFromResource(spnFreq.context, n.opp_khz.map { "${it/1000000} MHz" }.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnFreq.adapter = it }
                spnFreq.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                    override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                    override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                        onChange("gpu.node.${n.name}.max_freq", n.opp_khz[pos])
                    }
                }
            } else {
                spnFreq.visibility = View.GONE
            }
        }
    }

    class IoBlockViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tvTitle: TextView = view.findViewById(R.id.tvKnobTitle)
        private val spnSched: Spinner = view.findViewById(R.id.spnFreq) // reuse freq spinner id
        fun bind(b: IoBlockKnob) {
            tvTitle.text = b.name
            ArrayAdapter.createFromResource(spnSched.context, b.schedulers.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnSched.adapter = it }
            spnSched.setSelection(b.schedulers.indexOf(b.cur).coerceAtLeast(0))
            spnSched.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                    onChange("io.block.${b.name}.sched", b.schedulers[pos])
                }
            }
        }
    }

    class NetworkViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tvTitle: TextView = view.findViewById(R.id.tvKnobTitle)
        private val spnTcp: Spinner = view.findViewById(R.id.spnGov)
        private val spnTfo: Spinner = view.findViewById(R.id.spnFreq)
        fun bind(item: Any) {
            when (item) {
                is List<*> -> { // tcp_cc list
                    tvTitle.text = "TCP Congestion Control"
                    ArrayAdapter.createFromResource(spnTcp.context, item.map { it.toString() }.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnTcp.adapter = it }
                }
                is com.hsin.model.TfoKnob -> {
                    tvTitle.text = "TCP Fast Open"
                    ArrayAdapter.createFromResource(spnTfo.context, (item.min..item.max).toList().toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnTfo.adapter = it }
                    spnTfo.setSelection(item.cur - item.min)
                    spnTfo.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                        override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                        override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                            onChange("network.tfo", item.min + pos)
                        }
                    }
                }
            }
        }
    }

    class DisplayViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tvTitle: TextView = view.findViewById(R.id.tvKnobTitle)
        private val spnMode: Spinner = view.findViewById(R.id.spnGov)
        private val spnRenderer: Spinner = view.findViewById(R.id.spnFreq) // reuse
        fun bind(item: Any) {
            when (item) {
                is List<*> -> { // modes_hz
                    tvTitle.text = "Refresh Rate (Hz)"
                    ArrayAdapter.createFromResource(spnMode.context, item.map { "${it} Hz" }.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnMode.adapter = it }
                }
                is com.hsin.model.DisplayKnobs -> {
                    tvTitle.text = "Renderer"
                    ArrayAdapter.createFromResource(spnRenderer.context, item.renderers.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnRenderer.adapter = it }
                    spnRenderer.setSelection(item.renderers.indexOf(item.cur_renderer).coerceAtLeast(0))
                    spnRenderer.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                        override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                        override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                            onChange("display.renderer", item.renderers[pos])
                        }
                    }
                }
                is com.hsin.model.DownscaleKnob -> {
                    tvTitle.text = "Downscale %"
                    // Use a SeekBar instead? For now Spinner with min..max
                    val vals = (item.min..item.max).toList()
                    ArrayAdapter.createFromResource(spnMode.context, vals.map { "$it%" }.toTypedArray(), android.R.layout.simple_spinner_item).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spnMode.adapter = it }
                    spnMode.setSelection(item.cur - item.min)
                    spnMode.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                        override fun onNothingSelected(p0: android.widget.AdapterView?) {}
                        override fun onItemSelected(p0: android.widget.AdapterView?, p1: View?, pos: Int, p3: Long) {
                            onChange("display.downscale", item.min + pos)
                        }
                    }
                }
            }
        }
    }

    class FeatureViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val tvTitle: TextView = view.findViewById(R.id.tvKnobTitle)
        private val sw: Switch = view.findViewById(R.id.swFeature)
        fun bind(item: Any) {
            when (item) {
                Boolean -> {
                    tvTitle.text = "Feature" // title from section will be separate
                    sw.isChecked = item
                    sw.setOnCheckedChangeListener { _, checked -> onChange("feature", checked) }
                }
            }
        }
    }
}