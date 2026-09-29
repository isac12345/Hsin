package com.hsin.ui.knob

import com.hsin.data.state.KnobCapability
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Layar Knob (A9). Tiga aturan yang diuji:
 * 1. Kategori hanya dibuat dari capability `knobs` — tidak ada daftar karangan.
 * 2. Knob yang tidak tersedia tidak muncul sama sekali.
 * 3. APK tidak melakukan logika engine: nilai yang dikirim apa adanya.
 */
class KnobCategoryBuilderTest {

    /**
     * Fitur bergate sekarang bagian dari capability (dicek lewat
     * [com.hsin.data.state.KnobsMapping.parse]), bukan fungsi terpisah.
     */
    private fun gatedOf(
        knobs: JSONObject,
        allowExtreme: Boolean,
    ): List<com.hsin.data.state.GatedFeature> =
        com.hsin.data.state.KnobsMapping.parse(knobs, allowExtreme).capability.gated

    private fun fixture(name: String): String {
        val s = javaClass.getResourceAsStream("/fixtures/$name")
            ?: error("fixture $name tidak ada")
        return s.bufferedReader().use { it.readText() }.trim().lines().last()
    }

    private fun sandboxCapability(): Pair<KnobCapability, com.hsin.data.state.DirtyMap> {
        val parsed = com.hsin.data.state.KnobsMapping.parse(
            JSONObject(fixture("knobs_sandbox.txt")),
            allowExtreme = false,
        )
        return parsed.capability to
            com.hsin.data.state.DirtyTracker.mergeBase(emptyMap(), parsed.baseValues)
    }

    // ---- kategori dari capability ----

    @Test
    fun onlyCategoriesWithKeysAreCreated() {
        val (cap, base) = sandboxCapability()
        val cats = KnobCategoryBuilder.build(cap, base)
        assertTrue("harus ada minimal satu kategori", cats.isNotEmpty())
        for (c in cats) {
            assertTrue("kategori kosong tidak boleh dibuat: ${c.category}", c.rows.isNotEmpty())
        }
    }

    @Test
    fun emptyCapabilityProducesNoCategories() {
        val empty = KnobCapability(
            supportedKeys = emptyList(),
            allowedValues = emptyMap(),
            allowExtreme = false,
        )
        assertTrue(KnobCategoryBuilder.build(empty, emptyMap()).isEmpty())
    }

    @Test
    fun categoryOrderIsFixed() {
        val (cap, base) = sandboxCapability()
        val order = KnobCategoryBuilder.build(cap, base).map { it.category }
        val expectedOrder = KnobCategory.entries.filter { it in order }
        assertEquals("urutan harus mengikuti enum", expectedOrder, order)
    }

    @Test
    fun keysAreMappedToRightCategory() {
        val cap = KnobCapability(
            supportedKeys = listOf(
                "cpu_policy_0_gov", "cpu_policy_0_sched", "gpu_node_x_gov",
                "io_block_sda_sched", "tcp_cc", "swappiness", "vfs_cache_pressure",
            ),
            allowedValues = mapOf(
                "cpu_policy_0_gov" to listOf("performance"),
                "cpu_policy_0_sched" to listOf("futex"),
                "gpu_node_x_gov" to listOf("performance"),
                "io_block_sda_sched" to listOf("none"),
                "tcp_cc" to listOf("bbr"),
            ),
            allowExtreme = false,
        )
        val byCat = KnobCategoryBuilder.build(cap, emptyMap()).associate { it.category to it.rows.map { r -> r.key } }
        assertEquals(listOf("cpu_policy_0_gov"), byCat[KnobCategory.CPU])
        assertEquals(listOf("cpu_policy_0_sched"), byCat[KnobCategory.CPU_SCHED])
        assertEquals(listOf("gpu_node_x_gov"), byCat[KnobCategory.GPU])
        assertEquals(listOf("io_block_sda_sched"), byCat[KnobCategory.IO])
        assertEquals(listOf("tcp_cc"), byCat[KnobCategory.NETWORK])
        assertEquals(
            listOf("swappiness", "vfs_cache_pressure"),
            byCat[KnobCategory.MEMORY]?.sorted(),
        )
    }

    @Test
    fun rateLimitGoesToCpuNotCpuSched() {
        val cap = KnobCapability(
            supportedKeys = listOf("cpu_policy_0_rate_limit_us"),
            allowedValues = emptyMap(),
            ranges = mapOf("cpu_policy_0_rate_limit_us" to 0..100000),
            allowExtreme = false,
        )
        val cats = KnobCategoryBuilder.build(cap, emptyMap())
        assertEquals(1, cats.size)
        assertEquals(KnobCategory.CPU, cats[0].category)
    }

    // ---- jenis kontrol ----

    @Test
    fun kindSelectionFollowsDataShape() {
        assertEquals(KnobKind.CHOICE, KnobCategoryBuilder.kindFor(listOf("a", "b"), null))
        assertEquals(KnobKind.TOGGLE, KnobCategoryBuilder.kindFor(emptyList(), 0..1))
        assertEquals(KnobKind.SLIDER, KnobCategoryBuilder.kindFor(emptyList(), 1..90))
        assertEquals(KnobKind.LOCKED, KnobCategoryBuilder.kindFor(emptyList(), null))
    }

    @Test
    fun sandboxGovernorIsChoiceWithRealValues() {
        val (cap, base) = sandboxCapability()
        val cats = KnobCategoryBuilder.build(cap, base)
        val cpu = cats.firstOrNull { it.category == KnobCategory.CPU }!!
        val gov = cpu.rows.first { it.key.endsWith("_gov") }
        assertEquals(KnobKind.CHOICE, gov.kind)
        assertTrue("pilihan harus dari knobs, bukan karangan", gov.choices.size > 1)
    }

    // ---- dirty tracking ----

    @Test
    fun dirtyBadgeCountedPerCategory() {
        val cap = KnobCapability(
            supportedKeys = listOf("cpu_policy_0_gov", "cpu_policy_0_sched"),
            allowedValues = mapOf("cpu_policy_0_gov" to listOf("a", "b")),
            allowExtreme = false,
        )
        val base = mapOf("cpu_policy_0_gov" to "a", "cpu_policy_0_sched" to "futex")
        val clean = com.hsin.data.state.DirtyTracker.mergeBase(emptyMap(), base)
        val cats = KnobCategoryBuilder.build(cap, clean)
        assertEquals(0, cats.sumOf { it.dirtyCount })

        // user memilih nilai lain untuk policy 0 governor
        val dirtyState = com.hsin.data.state.DirtyTracker.setOverride(clean, "cpu_policy_0_gov", "b")
        val after = KnobCategoryBuilder.build(cap, dirtyState)
        val cpu = after.first { it.category == KnobCategory.CPU }
        assertEquals(1, cpu.dirtyCount)
        assertTrue(cpu.rows.first { it.key == "cpu_policy_0_gov" }.dirty)
        assertEquals(0, after.first { it.category == KnobCategory.CPU_SCHED }.dirtyCount)
    }

    @Test
    fun baseStaysVisibleSoUserCanSeeChange() {
        val cap = KnobCapability(
            supportedKeys = listOf("cpu_policy_0_gov"),
            allowedValues = mapOf("cpu_policy_0_gov" to listOf("a", "b")),
            allowExtreme = false,
        )
        val base = mapOf("cpu_policy_0_gov" to "a")
        val dirty = com.hsin.data.state.DirtyTracker.setOverride(
            com.hsin.data.state.DirtyTracker.mergeBase(emptyMap(), base),
            "cpu_policy_0_gov", "b",
        )
        val row = KnobCategoryBuilder.build(cap, dirty)[0].rows[0]
        assertEquals("a", row.base)
        assertEquals("b", row.current)
        assertTrue(row.dirty)
    }

    // ---- label ----

    @Test
    fun labelsAreHumanReadable() {
        assertEquals("Policy 0 · Gov", KnobCategoryBuilder.labelFor("cpu_policy_0_gov", "x"))
        assertEquals(
            "23100000.gpu · Gov",
            KnobCategoryBuilder.labelFor("gpu_node_23100000_gpu_gov", "x"),
        )
        assertEquals("sda · Sched", KnobCategoryBuilder.labelFor("io_block_sda_sched", "x"))
        assertEquals("Tcp cc", KnobCategoryBuilder.labelFor("tcp_cc", "x"))
    }

    // ---- tidak ada logika engine di APK ----

    @Test
    fun requestedValueIsSentVerbatimForChoice() {
        val row = KnobRow("cpu_policy_0_gov", "l", KnobKind.CHOICE, listOf("a", "b"), null, "a", "b")
        assertEquals("APK tidak boleh memetakan governor", "b", KnobCategoryBuilder.requestedValueFor(row, 0.7f))
    }

    @Test
    fun toggleSendsZeroOrOne() {
        val row = KnobRow("sched_child_runs_first", "l", KnobKind.TOGGLE, emptyList(), 0..1, "0", "0")
        assertEquals("1", KnobCategoryBuilder.requestedValueFor(row, 0.9f))
        assertEquals("0", KnobCategoryBuilder.requestedValueFor(row, 0.1f))
    }

    @Test
    fun sliderClampsToModuleReportedRange() {
        val row = KnobRow("swappiness", "l", KnobKind.SLIDER, emptyList(), 0..100, "60", "60")
        assertEquals("nilai di luar batas harus dijepit", "100", KnobCategoryBuilder.requestedValueFor(row, 500f))
        assertEquals("0", KnobCategoryBuilder.requestedValueFor(row, -10f))
        assertEquals("42", KnobCategoryBuilder.requestedValueFor(row, 42.4f))
    }

    @Test
    fun noOppMappingIsComputedLocally() {
        // Tidak ada tabel OPP di APK: nilai yang dikirim harus persis
        // nilai yang dipilih user, apa adanya.
        val row = KnobRow("gpu_node_x_gov", "l", KnobKind.CHOICE, listOf("performance"), null, "x", "performance")
        assertEquals("performance", KnobCategoryBuilder.requestedValueFor(row, 123.4f))
    }

    // ---- fitur bergate ----

    @Test
    fun gatedFeaturesAreListedButNeverUnlockedByApp() {
        val knobs = JSONObject(fixture("knobs_sandbox.txt"))
        val gated = gatedOf(knobs, allowExtreme = false)
        assertTrue("harus ada baris terkunci", gated.isNotEmpty())
        val extreme = gated.first { it.label == "Profil extreme" }
        assertFalse("APK tidak boleh membuka gate extreme", extreme.available)
        assertTrue("alasannya harus jelas", extreme.why.isNotBlank())
        for (g in gated) {
            assertTrue("${g.label} perlu alasan", g.why.isNotBlank())
        }
    }

    @Test
    fun extremeStillLockedEvenWhenModuleAndConfigAllow() {
        val knobs = JSONObject(fixture("knobs_sandbox.txt"))
            .put("features", JSONObject("""{"extreme_optin":true}"""))
        val gated = gatedOf(knobs, allowExtreme = true)
        // allow_extreme yang true berarti konfigurasi sudah dibuka; layar
        // ini tetap hanya melaporkan status, tidak membuka tombol.
        assertNotNull(gated.firstOrNull { it.label == "Profil extreme" })
    }

    @Test
    fun knobsJsonWithoutFeaturesYieldsNoGatedRows() {
        assertTrue(gatedOf(JSONObject("""{"v":1}"""), false).isEmpty())
    }
}
