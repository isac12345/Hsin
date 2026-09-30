package com.hsin.data.state

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pemetaan `knobs` (kontrak §3.2) ke [KnobCapability] + peta base.
 * Diuji terhadap fixture sandbox nyata (`knobs_sandbox.txt`).
 */
class KnobsMappingTest {

    private fun sandboxKnobs(): JSONObject {
        val raw = javaClass.getResourceAsStream("/fixtures/knobs_sandbox.txt")
            ?: error("fixture knobs_sandbox.txt tidak ada")
        val text = raw.bufferedReader().use { it.readText() }.trim()
        return JSONObject(text.lines().last())
    }

    @Test
    fun parsesRealSandboxKnobsFixture() {
        val raw = sandboxKnobs()
        val parsed = KnobsMapping.parse(raw, allowExtreme = false)
        assertFalse("allow_extreme default false", parsed.capability.allowExtreme)
        // Di fixture sandbox, CPU didukung (2 policy) tapi GPU/IO/network tidak.
        // Yang harus benar: key yang ditawarkan mengikuti apa yang device
        //benar-benar mendukung, bukan asumsi.
        assertTrue(
            "cpu_policy_0_gov harus ada karena cpu.supported=true",
            parsed.capability.supportedKeys.contains("cpu_policy_0_gov"),
        )
        assertFalse(
            "tidak boleh menawarkan knob io saat io.supported=false",
            parsed.capability.supportedKeys.any { it.startsWith("io_block_") },
        )
        assertEquals(
            "nilai base governor harus dari knobs",
            raw.getJSONObject("cpu").getJSONArray("policies")
                .getJSONObject(0).optString("cur_gov"),
            parsed.baseValues["cpu_policy_0_gov"],
        )
    }

    @Test
    fun everySupportedKeyIsEditablePattern() {
        val parsed = KnobsMapping.parse(sandboxKnobs(), allowExtreme = false)
        val pat = Regex("^[a-z0-9_]+$")
        for (k in parsed.capability.supportedKeys) {
            assertTrue("key '$k' harus pola aman", pat.matches(k))
        }
    }

    @Test
    fun knobProfilesAreFilteredToKnownOnes() {
        // `knobs` di sandbox bisa memuat profil tak dikenal; hanya yang nyata
        // yang boleh ditawarkan ke user (kontrak §2).
        val knobs = JSONObject("""{"v":1,"profiles":["balanced","manual","jubah","agresif"]}""")
        val parsed = KnobsMapping.parse(knobs, allowExtreme = false)
        // Tidak ada key knob pada input minimal ini, tapi parsing tidak boleh error
        assertNotNull(parsed.capability)
        val withKeys = JSONObject("""
            {"v":1,"profiles":["balanced","jubah"],
             "network":{"supported":true,"tcp_cc":["cubic"],"cur_cc":"cubic"}}
        """.trimIndent())
        assertTrue(KnobsMapping.parse(withKeys, false).capability.allowedValues.containsKey("tcp_cc"))
    }

    @Test
    fun cpuGovernorKeysComeFromPerPolicyGovs() {
        val knobs = JSONObject("""
            {"v":1,"profiles":["manual"],"cpu":{"supported":true,"policies":[
              {"id":"0","govs":["performance","schedutil"],"cur_gov":"schedutil"},
              {"id":"6","govs":["performance"],"cur_gov":"performance"}
            ]}}
        """.trimIndent())
        val parsed = KnobsMapping.parse(knobs, allowExtreme = false)
        assertEquals(listOf("performance", "schedutil"), parsed.capability.allowedValues["cpu_policy_0_gov"])
        assertEquals("schedutil", parsed.baseValues["cpu_policy_0_gov"])
        assertEquals("performance", parsed.baseValues["cpu_policy_6_gov"])
    }

    @Test
    fun gpuNodeNameIsSanitizedLikeModule() {
        // Fixture sandbox nyata tidak punya node GPU (gpu.supported=false),
        // jadi kasus ini memakai input dengan bentuk yang sama seperti §3.2.
        val knobs = JSONObject("""
            {"v":1,"profiles":["manual"],"gpu":{"supported":true,"nodes":[
              {"name":"23100000.gpu","govs":["performance"],"cur_gov":"performance"}
            ]}}
        """.trimIndent())
        val parsed = KnobsMapping.parse(knobs, allowExtreme = false)
        assertTrue(
            "sanitasi titik jadi underscore",
            parsed.baseValues.containsKey("gpu_node_23100000_gpu_gov"),
        )
        assertEquals("performance", parsed.baseValues["gpu_node_23100000_gpu_gov"])
    }

    @Test
    fun sanitizeMatchesModuleRules() {
        assertEquals("23100000_gpu", KnobsMapping.sanitize("23100000.gpu"))
        assertEquals("a_b_c", KnobsMapping.sanitize("a-b.c"))
        assertEquals(40, KnobsMapping.sanitize("x".repeat(80)).length)
    }

    @Test
    fun ioSchedulerAndNetworkCcParsed() {
        val knobs = JSONObject("""
            {"v":1,"profiles":["manual"],
             "io":{"supported":true,"blocks":[
               {"name":"sda","schedulers":["[mq-deadline]","none"],"cur":"mq-deadline"}]},
             "network":{"supported":true,"tcp_cc":["cubic","reno","bbr"],"cur_cc":"cubic"}}
        """.trimIndent())
        val parsed = KnobsMapping.parse(knobs, allowExtreme = false)
        assertTrue(parsed.capability.allowedValues.containsKey("io_block_sda_sched"))
        assertTrue(parsed.capability.allowedValues["tcp_cc"]!!.contains("bbr"))
        assertEquals("cubic", parsed.baseValues["tcp_cc"])
    }

    @Test
    fun unsupportedNodeIsNotOffered() {
        // zram tidak supported -> tidak boleh muncul sebagai pilihan
        val knobs = JSONObject("""
            {"v":1,"profiles":["manual"],
             "memory":{"supported":false,"swappiness":{"supported":false,"cur":0},
                       "zram":{"supported":false,"algos":[],"cur":""}}}
        """.trimIndent())
        val parsed = KnobsMapping.parse(knobs, allowExtreme = false)
        assertFalse(parsed.capability.allowedValues.containsKey("zram_algo"))
        assertFalse(parsed.baseValues.containsKey("swappiness"))
    }

    @Test
    fun allowExtremeFlagFlowsThrough() {
        val parsed = KnobsMapping.parse(sandboxKnobs(), allowExtreme = true)
        assertTrue(parsed.capability.allowExtreme)
    }

    @Test
    fun gpuTunablesParsedToEditableKeys() {
        val knobs = JSONObject("""
            {"v":1,"profiles":["manual"],
             "gpu_tunables":[{"node":"23100000.gpu","tunables":{
               "polling_interval":{"min":1,"max":1000,"cur":50,"supported":true,"writable":true},
               "up_threshold":{"min":1,"max":100,"cur":10,"supported":true,"writable":true},
               "down_differential":{"min":0,"max":100,"cur":5,"supported":true,"writable":true}
             }}]}
        """.trimIndent())
        val parsed = KnobsMapping.parse(knobs, false)
        assertTrue("gpu_tunables polling_interval harus ada", parsed.capability.supportedKeys.contains("gpu_node_23100000_gpu_polling_interval"))
        assertEquals("50", parsed.baseValues["gpu_node_23100000_gpu_polling_interval"])
        assertTrue("down_differential harus ada", parsed.capability.supportedKeys.contains("gpu_node_23100000_gpu_down_differential"))
    }

    @Test
    fun emptyKnobsYieldsEmptyCapability() {
        val parsed = KnobsMapping.parse(JSONObject("""{"v":1}"""), allowExtreme = false)
        assertNotNull(parsed.capability)
        assertTrue(parsed.capability.supportedKeys.isEmpty())
    }
}
