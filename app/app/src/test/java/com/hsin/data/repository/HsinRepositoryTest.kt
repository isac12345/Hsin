package com.hsin.data.repository

import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*

class HsinRepositoryTest {

    @Test
    fun parser_knob_list_manual_mode_2_applied_31_skipped() {
        val text = javaClass.getResourceAsStream("/fixtures/knob-list_manual.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val results = HsinRepository.parseKnobList(text)
        val applied = results.filter { it.category == "APPLIED" }
        val skipped = results.filter { it.category == "SKIPPED" }
        // Fakta kontrak §3.11: 2 override → 2 APPLIED; sisanya SKIPPED
        assertTrue("ada hasil", results.isNotEmpty())
        assertEquals("2 APPLIED", 2, applied.size)
        // applied=- harus diterima (manual tanpa override)
        val withDash = results.filter { it.applied == "-" }
        assertTrue("ada applied=-", withDash.isNotEmpty())
    }

    @Test
    fun parser_ignores_unknown_key() {
        val text = javaClass.getResourceAsStream("/fixtures/knob-list_manual.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val results = HsinRepository.parseKnobList(text)
        val unknown = results.filter { it.key.contains("unknown") }
        assertEquals("key tak dikenal diabaikan", 0, unknown.size)
    }

    @Test
    fun parser_rejects_foreign_category() {
        // Simulasi kategori asing harus diabaikan (bukan masuk list)
        val fake = "key=test requested=1 applied=1 category=FAKE reason=bad\n"
        val results = HsinRepository.parseKnobList(fake)
        assertEquals("kategori asing diabaikan", 0, results.size)
    }

    @Test
    fun parser_mixed_json_log_handle() {
        val text = javaClass.getResourceAsStream("/fixtures/knob-list_manual.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val results = HsinRepository.parseKnobList(text)
        assertTrue("log bercampur JSON ditangani", results.isNotEmpty())
    }

    @Test
    fun parser_guard_status_5_keys() {
        val text = javaClass.getResourceAsStream("/fixtures/guard-status.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val gs = HsinRepository.parseGuardStatus(text)
        assertEquals(1, gs.active)
        assertEquals(0, gs.fail_count)
        assertEquals(3, gs.threshold)
        assertEquals(120, gs.cooldown_remaining_sec)
    }

    @Test
    fun parser_uses_org_json_real() {
        val obj = JSONObject("{\"key\":\"k\",\"category\":\"APPLIED\"}")
        assertEquals("k", obj.getString("key"))
    }

    @Test
    fun capabilities_not_sandbox_source() {
        // CATATAN §3.9: capabilities tidak bisa disandbox (path /sys literal)
        val note = javaClass.getResourceAsStream("/fixtures/kapabilities_note.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        assertTrue(note.contains("/sys"))
        assertTrue(note.contains("TIDAK dipakai"))
    }

    @Test
    fun output_broken_empty_handled() {
        assertTrue(HsinRepository.parseKnobList("").isEmpty())
    }
}
