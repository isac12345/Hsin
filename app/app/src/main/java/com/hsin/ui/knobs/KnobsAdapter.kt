package com.hsin.ui.knobs

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.CompoundButton
import android.widget.Spinner
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.hsin.R

/**
 * Adapter datar untuk [KnobRow]. Satu ViewHolder per tipe baris, tanpa
 * cast antar-tipe dan tanpa daftar bersarang.
 */
class KnobsAdapter(
    private val onChoice: (KnobRow.Choice, String) -> Unit,
    private val onToggle: (KnobRow.Toggle, Boolean) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private var rows: List<KnobRow> = emptyList()

    fun submit(newRows: List<KnobRow>) {
        rows = newRows
        notifyDataSetChanged()
    }

    override fun getItemCount(): Int = rows.size

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is KnobRow.Header -> TYPE_HEADER
        is KnobRow.Choice -> TYPE_CHOICE
        is KnobRow.Toggle -> TYPE_TOGGLE
        is KnobRow.ReadOnly -> TYPE_READONLY
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_HEADER -> HeaderHolder(inflater.inflate(R.layout.item_section_header, parent, false))
            TYPE_CHOICE -> ChoiceHolder(inflater.inflate(R.layout.item_knob_choice, parent, false))
            TYPE_TOGGLE -> ToggleHolder(inflater.inflate(R.layout.item_knob_toggle, parent, false))
            else -> ReadOnlyHolder(inflater.inflate(R.layout.item_knob_readonly, parent, false))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = rows[position]) {
            is KnobRow.Header -> (holder as HeaderHolder).bind(row)
            is KnobRow.Choice -> (holder as ChoiceHolder).bind(row)
            is KnobRow.Toggle -> (holder as ToggleHolder).bind(row)
            is KnobRow.ReadOnly -> (holder as ReadOnlyHolder).bind(row)
        }
    }

    class HeaderHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view.findViewById(R.id.tvSectionTitle)
        fun bind(row: KnobRow.Header) {
            title.text = row.title
        }
    }

    class ReadOnlyHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view.findViewById(R.id.tvKnobTitle)
        private val value: TextView = view.findViewById(R.id.tvKnobValue)
        fun bind(row: KnobRow.ReadOnly) {
            title.text = row.title
            value.text = row.value
        }
    }

    inner class ChoiceHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view.findViewById(R.id.tvKnobTitle)
        private val hint: TextView = view.findViewById(R.id.tvKnobHint)
        private val spinner: Spinner = view.findViewById(R.id.spnKnobValue)

        fun bind(row: KnobRow.Choice) {
            title.text = row.title
            val ctx = itemView.context

            if (row.options.isEmpty()) {
                hint.text = row.hint ?: "tidak ada pilihan di perangkat ini"
                hint.visibility = View.VISIBLE
                spinner.adapter = null
                spinner.isEnabled = false
                return
            }

            hint.text = row.hint.orEmpty()
            hint.visibility = if (row.hint.isNullOrEmpty()) View.GONE else View.VISIBLE

            // createFromResource() hanya menerima @ArrayRes (Int), jadi untuk
            // daftar dari JSON harus lewat constructor ArrayAdapter langsung.
            val adapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, row.options)
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            spinner.adapter = adapter
            spinner.isEnabled = row.enabled
            if (row.selectedIndex in row.options.indices) {
                spinner.setSelection(row.selectedIndex, false)
            }

            spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onNothingSelected(parent: AdapterView<*>?) = Unit
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    onChoice(row, row.options[position])
                }
            }
        }
    }

    inner class ToggleHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view.findViewById(R.id.tvKnobTitle)
        private val hint: TextView = view.findViewById(R.id.tvKnobHint)
        private val toggle: CompoundButton = view.findViewById(R.id.swKnob)

        fun bind(row: KnobRow.Toggle) {
            title.text = row.title
            hint.text = row.hint.orEmpty()
            hint.visibility = if (row.hint.isNullOrEmpty()) View.GONE else View.VISIBLE

            // Lepas listener sebelum memasang listener baru; kalau tidak,
            // onToggle ikut terpanggil saat baris di-recycle.
            toggle.setOnCheckedChangeListener(null)
            toggle.isChecked = row.checked
            toggle.isEnabled = row.enabled
            toggle.setOnCheckedChangeListener { _, checked -> onToggle(row, checked) }
        }
    }

    private companion object {
        const val TYPE_HEADER = 0
        const val TYPE_CHOICE = 1
        const val TYPE_TOGGLE = 2
        const val TYPE_READONLY = 3
    }
}
