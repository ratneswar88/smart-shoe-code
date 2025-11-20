package com.smartshoe.shoeml_learning

import android.app.Application
import android.util.Log
import io.reactivex.plugins.RxJavaPlugins

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // Ignore Rx “Undeliverable” from BLE disconnects; log anything else.
        RxJavaPlugins.setErrorHandler { e ->
            val msg = e?.toString() ?: "null"
            if (msg.contains("UndeliverableException", true) ||
                msg.contains("BleDisconnectedException", true)) {
                Log.w("RxJava", "Ignored BLE disconnect: $msg")
                return@setErrorHandler
            }
            Log.e("RxJava", "Unhandled Rx error", e)
        }
    }
}
