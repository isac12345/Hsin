package com.hsin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AdaptParseTest {
    @Test fun casStripIsNull() {
        val r = parseAdaptList("bin.mt.plus.canary beban=1 cas=- sesi=6 p1_min=0 rata=12 jank=50% stall=5087ms terakhir=2026-11-14 12:49")
        assertEquals(1, r.size)
        assertNull(r[0].bebanCas)
        assertEquals(1, r[0].beban)
        assertEquals(50, r[0].jank)
        assertEquals(5087, r[0].stallMs)
        assertEquals("2026-11-14 12:49", r[0].terakhir)
    }

    @Test fun oldModuleWithoutCas() {
        val r = parseAdaptList("com.axis.net beban=0 sesi=4 p1_min=0 rata=8 jank=14% stall=5784ms terakhir=2026-11-14 17:39")
        assertEquals(1, r.size)
        assertNull(r[0].bebanCas)
        assertEquals(0, r[0].beban)
    }

    @Test fun sortedNewestFirst() {
        val r = parseAdaptList("a.b beban=0 terakhir=2026-11-13 10:00\nc.d beban=1 terakhir=2026-11-14 09:00\n")
        assertEquals("c.d", r[0].pkg)
    }
}
