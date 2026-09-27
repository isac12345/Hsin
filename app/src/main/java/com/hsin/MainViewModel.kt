package com.hsin

import androidx.lifecycle.ViewModel
import androidx.lifecycle.MutableLiveData
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

class MainViewModel : ViewModel() {
    val errorMessage = MutableLiveData<String>()

    fun reportError(message: String) {
        errorMessage.value = message
    }

    fun clearError() {
        errorMessage.value = null
    }
}