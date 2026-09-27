package com.hsin

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel

/**
 * Menyimpan pesan sekali-pakai untuk Snackbar. `postMessage` dipanggil dari
 * thread mana pun (fragmen memakai lifecycleScope, yaitu Main dispatcher),
 * `clearMessage` dipakai setelah pesan ditampilkan supaya tidak berulang.
 */
class MainViewModel : ViewModel() {

    private val _messages = MutableLiveData<String>()
    val messages: LiveData<String> = _messages

    fun postMessage(text: String) {
        _messages.value = text
    }

    fun clearMessage() {
        _messages.value = null
    }
}
