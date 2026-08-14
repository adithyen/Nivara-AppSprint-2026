package com.nivara.nivara

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "ola_native_map_view",
            OlaMapViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
