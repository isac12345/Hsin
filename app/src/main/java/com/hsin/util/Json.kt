package com.hsin.util

import kotlinx.serialization.json.Json

object Json {
    val default: Json = Json { ignoreUnknownKeys = true }
}