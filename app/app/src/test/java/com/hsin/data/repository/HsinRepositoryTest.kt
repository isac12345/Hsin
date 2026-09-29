package com.hsin.data.repository

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
    fun parser_knob_list_manual_matches_contract_fixture() {
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
    fun key_equals_inside_log_line_is_not_parsed_as_knob() {
        // Baris log yang memuat "key=" di tengah TIDAK boleh jadi entri knob
        // (parser harus anchor di awal baris).
        val noisy = "INFO apply: wrote key=vfs_cache_pressure to sysfs\n" +
            "key=io_block_sda_readahead requested=2048 applied=2048 category=APPLIED reason=\"dipakai sesuai permintaan\"\n" +
            "{\"count\":1,\"overrides\":{\"io_block_sda_readahead\":\"2048\"}}\n"
        val res = HsinRepository.parseKnobList(noisy)
        assertTrue(res is HsinRepository.KnobParseResult.Ok)
        val ok = res as HsinRepository.KnobParseResult.Ok
        assertEquals("hanya 1 entri knob dari 1 baris key= di awal", 1, ok.items.size)
        assertEquals("io_block_sda_readahead", ok.items[0].key)
    }

    @Test
    fun parser_accepts_all_five_module_categories() {
        // Set kategori dari kode modul (kontrak §4).
        for (cat in listOf("APPLIED", "SKIPPED", "FALLBACK", "UNAVAILABLE", "FAILED")) {
            val line = "key=swappiness requested=60 applied=60 category=$cat reason=\"x\"\n"
            val res = HsinRepository.parseKnobList(line)
            assertTrue("$cat harus valid, dapat: $res", res is HsinRepository.KnobParseResult.Ok)
        }
    }

    @Test
    fun reason_with_quoted_spaces_is_parsed_fully() {
        val res = HsinRepository.parseKnobList(
            "key=sched_child_runs_first requested=(manual) applied=- category=SKIPPED reason=\"tidak diatur (mode manual)\"\n"
        )
        val ok = res as HsinRepository.KnobParseResult.Ok
        assertEquals("tidak diatur (mode manual)", ok.items[0].reason)
    }

    @Test
    fun guard_status_reads_json_when_keyvalue_lines_absent() {
        val jsonOnly = "{\"active\":1,\"fail_count\":2,\"threshold\":2,\"cooldown_remaining_sec\":86400,\"last_reason\":\"boot gagal\"}\n"
        val gs = HsinRepository.parseGuardStatus(jsonOnly)
        assertNotNull("JSON saja harus terbaca", gs)
        assertEquals(1, gs!!.active)
        assertEquals(86400, gs.cooldownRemainingSec)
    }

    @Test
    fun status_json_extracted_and_unknown_keys_ignored() {
        val text = javaClass.getResourceAsStream("/fixtures/status_ok.txt")
            ?.bufferedReader()?.use { it.readText() } ?: error("fixture status_ok.txt hilang")
        val json = HsinRepository.parseStatus(text)
        assertNotNull("JSON status harus terbaca", json)
        assertNotNull("battery_pct harus terbaca", HsinRepository.statusInt(json!!, "battery_pct"))
        // key tak dikenal tidak boleh exception
        assertNull(HsinRepository.statusInt(json, "field_palsu_yang_tidak_ada"))
    }

    @Test
    fun status_broken_or_empty_returns_null() {
        assertNull(HsinRepository.parseStatus(""))
        assertNull(HsinRepository.parseStatus("bukan json sama sekali"))
        assertNull(HsinRepository.parseStatus("{broken"))
    }

    @Test
    fun status_sentinel_values_not_treated_as_readable() {
        // Kontrak §3.1 + aturan A11: -1 dan 0 adalah sentinel "tidak tersedia",
        // bukan angka valid yang boleh ditampilkan apa adanya.
        val json = org.json.JSONObject(
            "{\"battery_pct\":-1,\"refresh_hz\":0,\"cpu_load_x100\":235}"
        )
        assertFalse("battery_pct=-1 = sentinel", HsinRepository.statusReadable(json, "battery_pct"))
        assertFalse("refresh_hz=0 = sentinel", HsinRepository.statusReadable(json, "refresh_hz"))
        assertTrue("235 = nilai asli", HsinRepository.statusReadable(json, "cpu_load_x100"))
        // Nilai mentah tetap bisa diambil lewat statusInt bila memang dibutuhkan
        assertEquals(Integer.valueOf(-1), HsinRepository.statusInt(json, "battery_pct"))
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
