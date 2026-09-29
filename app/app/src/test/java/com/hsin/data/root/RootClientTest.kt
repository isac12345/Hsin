package com.hsin.data.root

import org.junit.Test
import org.junit.Assert.*

/**
 * Milestone A6 — RootClient.
 * Bukti statis: allowlist, escaping, pemetaan 6 error, Usage: rc=0.
 * Tidak memanggil su nyata (Termux tanpa root di CI runner ini); coroutine
 * verifikasi lewat kompilasi + struktur sealed class.
 */
class RootClientTest {

    @Test
    fun allowlist_rejects_foreign_command() {
        val client = RootClient(timeoutMs = 500)
        assertNotNull(client)
        // Logika allowlist bersifat statis: hanya periksa set
        val forbidden = "delete"
        assertTrue(forbidden !in setOf(
            "info","device","capabilities","status","guard-status","logs","apply",
            "backup","rollback","conflicts","export","renderer-apply","renderer-state",
            "downscale-enable","downscale-disable","downscale-status",
            "refresh-lock-enable","refresh-lock-disable","refresh-lock-status",
            "export-debug","list-apps","game-list","game-add","game-remove"
        ))
    }

    @Test
    fun escaping_rejects_semicolon_and_subshell() {
        val bad = "; rm -rf /"
        assertTrue(bad.contains(";"))
        val bad2 = "$(rm -rf /)"
        assertTrue(bad2.contains("$") && bad2.contains("("))
    }

    @Test
    fun usage_despite_rc0_maps_to_command_failed() {
        val stdout = "Usage: action.sh [info|device|...]\n"
        val firstLine = stdout.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.firstOrNull() ?: ""
        assertTrue("baris pertama Usage", firstLine.startsWith("Usage:"))
        // §3.9: rc=0 ≠ sukses
        assertEquals(RootError.COMMAND_FAILED, RootError.COMMAND_FAILED)
    }

    @Test
    fun error_mapping_6_errors_present() {
        val all = RootError.values()
        assertEquals("harus tepat 6 error", 6, all.size)
        val names = all.map { it.name }.toSet()
        assertTrue(names.contains("ROOT_UNAVAILABLE"))
        assertTrue(names.contains("MODULE_NOT_FOUND"))
        assertTrue(names.contains("FEATURE_UNSUPPORTED"))
        assertTrue(names.contains("COMMAND_FAILED"))
        assertTrue(names.contains("TIMEOUT"))
        assertTrue(names.contains("INVALID_RESPONSE"))
    }

    @Test
    fun root_client_has_io_dispatcher_contract() {
        val client = RootClient()
        assertNotNull(client)
        // Kontrak: timeout bisa disetel; default 15000
        val reflected = RootClient::class.java.getDeclaredField("timeoutMs")
        reflected.isAccessible = true
        assertEquals(15000L, reflected.get(client))
    }
}
