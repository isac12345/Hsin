package com.hsin

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import com.hsin.model.DeviceResponse
import com.hsin.model.KnobOverrides
import com.hsin.model.KnobsResponse
import com.hsin.model.StatusResponse

/**
 * Jembatan app -> modul HSIN. Semua komunikasi lewat `su -c` ke
 * action.sh; tidak ada tuning yang diterapkan dari sisi app (semua
 * keputusan user disimpan di modul).
 */
class HsinRepository(private val modulePath: String = MODULE_PATH) {

    companion object {
        const val MODULE_PATH = "/data/adb/modules/hsin"
        private const val TIMEOUT_MS = 20_000L
        private val json = Json { ignoreUnknownKeys = true }
    }

    private suspend fun action(name: String, vararg args: String): String =
        withContext(Dispatchers.IO) {
            val tokens = arrayOf("sh", "$modulePath/action.sh", name, *args)
            val result = RootExec.execTokens(*tokens, timeoutMs = TIMEOUT_MS)
            if (!result.success) throw HsinException(result.stdout)
            result.stdout
        }

    /**
     * `action.sh status` mencetak baris lain sebelum JSON (mis. hasil cek
     * game boost), jadi ambil baris non-kosong TERAKHIR untuk diparse.
     */
    private fun lastJsonLine(stdout: String): String =
        stdout.lineSequence().map { it.trim() }.lastOrNull { it.startsWith("{") }
            ?: throw HsinException("tidak ada JSON di output: ${stdout.take(200)}")

    suspend fun knobs(): KnobsResponse = json.decodeFromString(lastJsonLine(action("knobs")))

    suspend fun status(): StatusResponse = json.decodeFromString(lastJsonLine(action("status")))

    suspend fun device(): DeviceResponse = json.decodeFromString(lastJsonLine(action("device")))

    suspend fun knobList(): KnobOverrides = json.decodeFromString(lastJsonLine(action("knob-list")))

    /** Simpan satu override knob. [value] harus sudah diformat (mis. "schedutil"). */
    suspend fun knobSet(key: String, value: String) {
        action("knob-set", key, value)
    }

    suspend fun knobReset() {
        action("knob-reset")
    }

    /** Setel salah satu dari 7 kunci yang di-whitelist modul. */
    suspend fun configSet(key: String, value: String) {
        action("config-set", key, value)
    }

    suspend fun apply(profile: String) {
        action("apply", profile)
    }

    suspend fun logs(type: String): String = action("logs", type)

    suspend fun backup() {
        action("backup")
    }

    suspend fun rollback() {
        action("rollback")
    }
}

class HsinException(message: String) : Exception(message)
