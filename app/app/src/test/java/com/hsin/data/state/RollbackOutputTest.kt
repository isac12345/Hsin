package com.hsin.data.state

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Parsing keluaran `rollback` (kontrak §2):
 * ```
 * Rolling back...
 * Restore 20260929_222255 done. ok=6 fail=0
 * OK: Rollback complete
 * ```
 * Angka di sini menentukan apakah user diberi tahu bahwa pemulihannya
 * benar-benar berhasil, jadi parser harus jujur dan tidak menebak.
 */
class RollbackOutputTest {

    @Test
    fun parsesRealSandboxOutput() {
        val output = """
            Rolling back...
            Restore 20260929_222255 done. ok=6 fail=0
            OK: Rollback complete
        """.trimIndent()
        val detail = parseRollbackDetail(output)
        assertEquals(6 to 0, detail)
    }

    @Test
    fun detectsPartialFailure() {
        val output = "Restore 20260101_000000 done. ok=3 fail=2"
        assertEquals(3 to 2, parseRollbackDetail(output))
    }

    @Test
    fun nothingToRestoreIsSuccessNotFailure() {
        val output = "Restore 20260101_000000 done. ok=0 fail=0"
        assertEquals(0 to 0, parseRollbackDetail(output))
    }

    @Test
    fun missingDetailLineReturnsNull() {
        assertNull("tidak boleh mengarang angka", parseRollbackDetail("OK: Rollback complete"))
        assertNull(parseRollbackDetail(""))
    }

    @Test
    fun partialLineWithoutBothNumbersReturnsNull() {
        assertNull(parseRollbackDetail("Restore 20260101 done. ok=5"))
    }
}
