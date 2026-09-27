package com.hsin

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

class HsinRepository {
    companion object {
        private const val MODULE_PATH = "/data/adb/modules/hsin"
        private const val TIMEOUT_MS = 20000L
        private val json = Json { ignoreUnknownKeys = true }
    }

    private fun runCmd(vararg tokens: String): String = RootExec.execTokens(*tokens, TIMEOUT_MS).let { result ->
        if (!result.success) throw RuntimeException(result.stdout)
        result.stdout
    }

    suspend fun knobs(): KnobsResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "knobs")
        Json { ignoreUnknownKeys = true }.decodeFromString<KnobsResponse>(out)
    }

    suspend fun status(): StatusResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "status")
        Json { ignoreUnknownKeys = true }.decodeFromString<StatusResponse>(out)
    }

    suspend fun device(): DeviceResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "device")
        Json { ignoreUnknownKeys = true }.decodeFromString<DeviceResponse>(out)
    }

    suspend fun apply(profile: String): ApplyResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "apply", profile)
        try {
            Json { ignoreUnknownKeys = true }.decodeFromString<ApplyResponse>(out)
        } catch (_: Exception) {
            ApplyResponse(success = true, message = "Applied $profile")
        }
    }

    suspend fun configSet(key: String, value: String): ConfigSetResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "config-set", key, value)
        try {
            Json { ignoreUnknownKeys = true }.decodeFromString<ConfigSetResponse>(out)
        } catch (_: Exception) {
            ConfigSetResponse(success = true, message = "Set $key=$value")
        }
    }

    suspend fun configGet(): Map<String, String> = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "config-get")
        try {
            Json { ignoreUnknownKeys = true }.decodeFromString<Map<String, String>>(out)
        } catch (_: Exception) {
            emptyMap()
        }
    }

    suspend fun logs(type: String = "all"): String = withContext(Dispatchers.IO) {
        runCmd("sh", "$MODULE_PATH/action.sh", "logs", type)
    }

    suspend fun gameList(): GameListResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "game-list")
        try {
            Json { ignoreUnknownKeys = true }.decodeFromString<GameListResponse>(out)
        } catch (_: Exception) {
            GameListResponse(emptyList())
        }
    }

    suspend fun gameAdd(pkg: String): Boolean = withContext(Dispatchers.IO) {
        runCmd("sh", "$MODULE_PATH/action.sh", "game-add", pkg).contains("success") || true
    }

    suspend fun gameRemove(pkg: String): Boolean = withContext(Dispatchers.IO) {
        runCmd("sh", "$MODULE_PATH/action.sh", "game-remove", pkg).contains("success") || true
    }

    suspend fun backup(): BackupResponse = withContext(Dispatchers.IO) {
        val out = runCmd("sh", "$MODULE_PATH/action.sh", "backup")
        try {
            Json { ignoreUnknownKeys = true }.decodeFromString<BackupResponse>(out)
        } catch (_: Exception) {
            BackupResponse(success = true, path = "backup created")
        }
    }

    suspend fun configGetRaw(): String = withContext(Dispatchers.IO) {
        runCmd("sh", "$MODULE_PATH/action.sh", "config-get")
    }
}