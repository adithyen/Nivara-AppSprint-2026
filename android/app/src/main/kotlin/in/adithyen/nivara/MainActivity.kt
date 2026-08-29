package `in`.adithyen.nivara

import `in`.adithyen.nivara.R
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SHORTCUT_CHANNEL = "in.adithyen.nivara/shortcuts"
    private var pendingRoute: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "ola_native_map_view",
            OlaMapViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHORTCUT_CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pinSensorWatchShortcut" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val shortcutManager = getSystemService(ShortcutManager::class.java)
                        if (shortcutManager != null && shortcutManager.isRequestPinShortcutSupported) {
                            val pinIntent = Intent(applicationContext, MainActivity::class.java).apply {
                                action = Intent.ACTION_VIEW
                                putExtra("route", "/sensorwatch?autoStart=true")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            val pinShortcutInfo = ShortcutInfo.Builder(context, "sensorwatch_drive_shortcut")
                                .setShortLabel("SensorWatch Drive")
                                .setLongLabel("Instant SensorWatch Road Monitor")
                                .setIcon(Icon.createWithResource(context, R.mipmap.ic_launcher))
                                .setIntent(pinIntent)
                                .build()

                            val pinnedShortcutCallbackIntent = shortcutManager.createShortcutResultIntent(pinShortcutInfo)
                            val successCallback = PendingIntent.getBroadcast(
                                context,
                                0,
                                pinnedShortcutCallbackIntent,
                                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                            )

                            val pinned = shortcutManager.requestPinShortcut(pinShortcutInfo, successCallback.intentSender)
                            result.success(pinned)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getInitialShortcutRoute" -> {
                    val route = pendingRoute ?: intent?.getStringExtra("route")
                    pendingRoute = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra("route")
        if (route != null) {
            pendingRoute = route
            channel?.invokeMethod("onShortcutTriggered", route)
        }
    }
}
