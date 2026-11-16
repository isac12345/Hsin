package com.hsin

import org.junit.Assert.assertEquals
import org.junit.Test

class DsValueTest {
    @Test fun formatsWithDot() {
        assertEquals("0.73", dsValue(73))
        assertEquals("0.70", dsValue(70))
        assertEquals("0.10", dsValue(10))
    }
    @Test fun hundredIsOff() {
        assertEquals("off", dsValue(100))
        assertEquals("off", dsValue(120))
    }
    @Test fun clampsLow() {
        assertEquals("0.10", dsValue(3))
    }
}
