package com.opennutritracker.ont.opennutritracker.fork

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Whether Health Connect grants are held, for the fork's imports. The health plugin answers this
 * in a coroutine with no handler, so a rate-limited or dead Health Connect ends the process;
 * upstream's workout check goes around it the same way. Here the failure reaches Dart as an error.
 * Registered by seam S180 in MainActivity.
 *
 * `hasGrants` takes `names` (`READ_WEIGHT`, …) and answers a bool.
 */
class HealthGrantsChannel(private val context: Context, engine: FlutterEngine) {
    private val scope = CoroutineScope(Dispatchers.Main)

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "openbite/health_grants")
            .setMethodCallHandler { call, result ->
                if (call.method != "hasGrants") return@setMethodCallHandler result.notImplemented()
                val needed = call.argument<List<String>>("names").orEmpty()
                    .map { "android.permission.health.$it" }
                scope.launch {
                    try {
                        val granted = HealthConnectClient.getOrCreate(context)
                            .permissionController.getGrantedPermissions()
                        result.success(granted.containsAll(needed))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        result.error("health_connect_unavailable", e.message, null)
                    }
                }
            }
    }
}
