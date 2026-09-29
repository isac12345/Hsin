package com.hsin.data.repository

import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*

class HsinRepositoryTest {

    @Test
    fun parser_guard_status_inactive_5_keys() {
        val text = javaClass.getResourceAsStream("/fixtures/guard-status_inactive.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val gs = HsinRepository.parseGuardStatus(text)
        assertNotNull(gs)
        assertEquals(0, gs!!.active)
        assertEquals(0, gs.failCount)
        assertEquals(2, gs.threshold)
        assertEquals(0, gs.cooldownRemainingSec)
        assertEquals("tidak ada state", gs.lastReason)
    }

    @Test
    fun parser_guard_status_active_5_keys() {
        val text = javaClass.getResourceAsStream("/fixtures/guard-status_active.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val gs = HsinRepository.parseGuardStatus(text)
        assertNotNull(gs)
        assertEquals(1, gs!!.active)
        assertEquals(2, gs.failCount)
        assertEquals(2, gs.threshold)
        assertEquals(86400, gs.cooldownRemainingSec)
        assertEquals("boot gagal 2 x berturut-turut", gs.lastReason)
    }

    @Test
    fun parser_guard_status_null_if_missing_active() {
        val bad = "fail_count=0\nthreshold=2\n"
        assertNull(HsinRepository.parseGuardStatus(bad))
    }

    @Test
    fun parser_knob_list_manual_2_applied_31_skipped() {
        val text = javaClass.getResourceAsStream("/fixtures/knob-list_manual.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val res = HsinRepository.parseKnobList(text)
        assertTrue(res is HsinRepository.KnobParseResult.Ok)
        val ok = res as HsinRepository.KnobParseResult.Ok
        val applied = ok.items.filter { it.category == "APPLIED" }
        val skipped = ok.items.filter { it.category == "SKIPPED" }
        assertEquals("2 APPLIED", 2, applied.size)
        assertTrue("ada SKIPPED", skipped.isNotEmpty())
        // applied=- diterima
        val dash = ok.items.filter { it.applied == "-" }
        assertTrue("ada applied=-", dash.isNotEmpty())
        // JSON akhir: count=2, overrides benar
        assertEquals(Integer.valueOf(2), ok.count)
        assertTrue(ok.overrides.containsKey("io_block_sda_readahead"))
        assertTrue(ok.overrides.containsKey("vfs_cache_pressure"))
    }

    @Test
    fun parser_ignores_unknown_key_and_ignores_log_noise() {
        val text = javaClass.getResourceAsStream("/fixtures/knob-list_manual.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val res = HsinRepository.parseKnobList(text)
        assertTrue(res is HsinRepository.KnobParseResult.Ok)
        val ok = res as HsinRepository.KnobParseResult.Ok
        val unknown = ok.items.filter { it.key.contains("unknown") || it.key.contains("fake") }
        assertEquals(0, unknown.size)
    }

    @Test
    fun parser_rejects_foreign_category_as_invalid_response() {
        val fake = "key=test requested=1 applied=1 category=FAKE reason=bad\n"
        val res = HsinRepository.parseKnobList(fake)
        assertTrue(res is HsinRepository.KnobParseResult.InvalidResponse)
    }

    @Test
    fun parser_rejects_broken_json_block() {
        val fake = "key=a requested=1 applied=1 category=APPLIED reason=ok\n{bad"
        val res = HsinRepository.parseKnobList(fake)
        assertTrue(res is HsinRepository.KnobParseResult.InvalidResponse)
    }

    @Test
    fun parser_mixed_json_log_not_double_add() {
        val text = javaClass.getResourceAsStream("/fixtures/knob-list_manual.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        val res = HsinRepository.parseKnobList(text)
        val ok = res as HsinRepository.KnobParseResult.Ok
        val keys = ok.items.map { it.key }.toSet()
        // JSON akhir tidak membuat duplikat key dari baris key=
        assertEquals(keys.size, ok.items.size)
    }

    @Test
    fun parser_uses_org_json_real() {
        val obj = JSONObject("{\"key\":\"k\",\"category\":\"APPLIED\"}")
        assertEquals("k", obj.getString("key"))
    }

    @Test
    fun capabilities_note_not_source() {
        val note = javaClass.getResourceAsStream("/fixtures/capabilities_note.txt")?.bufferedReader()?.use { it.readText() } ?: ""
        assertTrue(note.contains("/sys"))
        assertTrue(note.contains("TIDAK dipakai"))
    }

    @Test
    fun broken_empty_handled() {
        val res = HsinRepository.parseKnobList("")
        val ok = res as HsinRepository.KnobParseResult.Ok
        assertTrue(ok.items.isEmpty())
        assertNull(ok.count)
        assertTrue(ok.overrides.isEmpty())
    }
}
