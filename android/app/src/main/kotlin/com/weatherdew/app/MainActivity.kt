package com.weatherdew.app

import com.weatherdew.app.widgets.WidgetUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The app pings this after fetching fresh weather or changing a
        // widget-visible setting (see lib/services/widget_bridge.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "weatherdew/widgets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sync" -> {
                        WidgetUpdater.syncFromApp(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
