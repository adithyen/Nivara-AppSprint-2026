package com.nivara.nivara

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import com.ola.mapsdk.camera.MapControlSettings
import com.ola.mapsdk.interfaces.MarkerEventListener
import com.ola.mapsdk.interfaces.OlaMapCallback
import com.ola.mapsdk.listeners.OlaMapsCameraListenerManager
import com.ola.mapsdk.listeners.OlaMapsListenerManager
import com.ola.mapsdk.model.OlaLatLng
import com.ola.mapsdk.model.OlaMarkerOptions
import com.ola.mapsdk.view.Marker
import com.ola.mapsdk.view.OlaMap
import com.ola.mapsdk.view.OlaMapView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class OlaMapViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String, Any?>
        return OlaNativeView(context, viewId, creationParams, messenger)
    }
}

class OlaNativeView(
    private val context: Context,
    private val viewId: Int,
    private val creationParams: Map<String, Any?>?,
    private val messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler {

    private val mapView: OlaMapView = OlaMapView(context)
    private var olaMap: OlaMap? = null
    private val channel: MethodChannel = MethodChannel(messenger, "com.nivara.ola_map_$viewId")
    private val markersMap = mutableMapOf<String, Marker>()

    init {
        channel.setMethodCallHandler(this)
        initializeMap()
    }

    private fun initializeMap() {
        val apiKey = creationParams?.get("apiKey") as? String ?: ""
        val initialLat = (creationParams?.get("initialLat") as? Number)?.toDouble() ?: 8.5241
        val initialLng = (creationParams?.get("initialLng") as? Number)?.toDouble() ?: 76.9366
        val initialZoom = (creationParams?.get("initialZoom") as? Number)?.toDouble() ?: 15.0
        val styleUrl = creationParams?.get("styleUrl") as? String
            ?: "https://api.olamaps.io/tiles/vector/v1/styles/default-dark-standard/style.json"

        // Pre-set style on internal IMap before getMap() triggers loadMap()
        try {
            val mapField = mapView.javaClass.getDeclaredField("map")
            mapField.isAccessible = true
            val iMap = mapField.get(mapView) as? com.ola.mapsdk.interfaces.IMap
            if (!styleUrl.isNullOrEmpty()) {
                iMap?.setStyle(styleUrl)
            }
        } catch (e: Exception) {
            android.util.Log.w("OlaNativeView", "Could not set initial style: ${e.message}")
        }

        val settings = MapControlSettings.Builder()
            .setRotateGesturesEnabled(true)
            .setScrollGesturesEnabled(true)
            .setZoomGesturesEnabled(true)
            .setCompassEnabled(true)
            .setTiltGesturesEnabled(true)
            .setDoubleTapGesturesEnabled(true)
            .build()

        mapView.getMap(
            apiKey = apiKey,
            olaMapCallback = object : OlaMapCallback {
                override fun onMapReady(map: OlaMap) {
                    olaMap = map
                    setupMap(initialLat, initialLng, initialZoom)
                    channel.invokeMethod("onMapReady", null)
                }

                override fun onMapError(error: String) {
                    channel.invokeMethod("onMapError", error)
                }
            },
            mapControlSettings = settings
        )
    }

    private fun setupMap(lat: Double, lng: Double, zoom: Double) {
        olaMap?.zoomToLocation(OlaLatLng(lat, lng), zoom)

        // Setup camera listeners
        olaMap?.setOnOlaMapsCameraIdleListener(object :
            OlaMapsCameraListenerManager.OnOlaMapsCameraIdleListener {
            override fun onOlaMapsCameraIdle() {
                val cameraPos = olaMap?.getCurrentOlaCameraPosition()
                val target = cameraPos?.target
                val args = mutableMapOf<String, Any?>()
                if (target != null) {
                    args["lat"] = target.latitude
                    args["lng"] = target.longitude
                }
                channel.invokeMethod("onCameraIdle", args)
            }
        })

        // Setup map click listener
        olaMap?.setOnMapClickedListener(object :
            OlaMapsListenerManager.OnOlaMapClickedListener {
            override fun onOlaMapClicked(olaLatLng: OlaLatLng) {
                channel.invokeMethod(
                    "onMapClicked",
                    mapOf("lat" to olaLatLng.latitude, "lng" to olaLatLng.longitude)
                )
            }
        })

        // Setup marker click listener
        olaMap?.setMarkerListener(object : MarkerEventListener {
            override fun onMarkerClicked(markerId: String) {
                channel.invokeMethod("onMarkerClicked", mapOf("markerId" to markerId))
            }
        })
    }

    override fun getView(): View = mapView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "animateCamera" -> {
                val lat = (call.argument<Number>("lat"))?.toDouble() ?: 8.5241
                val lng = (call.argument<Number>("lng"))?.toDouble() ?: 76.9366
                val zoom = (call.argument<Number>("zoom"))?.toDouble() ?: 15.0
                olaMap?.zoomToLocation(OlaLatLng(lat, lng), zoom)
                result.success(true)
            }
            "setStyleUrl" -> {
                val newStyleUrl = call.argument<String>("styleUrl") ?: ""
                if (newStyleUrl.isNotEmpty()) {
                    try {
                        val mapField = try {
                            olaMap?.javaClass?.getDeclaredField("map")
                        } catch (_: Exception) {
                            mapView.javaClass.getDeclaredField("map")
                        }
                        mapField?.isAccessible = true
                        val iMap = (if (olaMap != null) mapField?.get(olaMap) else mapField?.get(mapView)) as? com.ola.mapsdk.interfaces.IMap
                        iMap?.setStyle(newStyleUrl)
                        val nativeMap = iMap?.getNativeMap()?.getMap() as? org.maplibre.android.maps.MapLibreMap
                        nativeMap?.setStyle(org.maplibre.android.maps.Style.Builder().fromUri(newStyleUrl))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STYLE_ERROR", e.message, null)
                    }
                } else {
                    result.success(false)
                }
            }
            "addMarker" -> {
                val id = call.argument<String>("id") ?: ""
                val lat = (call.argument<Number>("lat"))?.toDouble() ?: 0.0
                val lng = (call.argument<Number>("lng"))?.toDouble() ?: 0.0
                val snippet = call.argument<String>("snippet") ?: ""
                val hexColor = call.argument<String>("color") ?: "#2ECC71"

                try {
                    // Remove existing marker with same id
                    markersMap[id]?.removeMarker()

                    val bitmap = createPinBitmap(hexColor)
                    val opts = OlaMarkerOptions.Builder()
                        .setMarkerId(id)
                        .setPosition(OlaLatLng(lat, lng))
                        .setIconBitmap(bitmap)
                        .setIsIconClickable(true)
                        .setIsInfoWindowDismissOnClick(true)
                        .setIsAnimationEnable(true)
                        .build()

                    val marker = olaMap?.addMarker(opts)
                    if (marker != null) {
                        markersMap[id] = marker
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("MARKER_ERROR", e.message, null)
                }
            }
            "removeMarker" -> {
                val id = call.argument<String>("id") ?: ""
                if (id.isNotEmpty()) {
                    try {
                        markersMap[id]?.removeMarker()
                        markersMap.remove(id)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REMOVE_MARKER_ERROR", e.message, null)
                    }
                } else {
                    result.success(false)
                }
            }
            "clearMarkers" -> {
                for ((_, m) in markersMap) {
                    try {
                        m.removeMarker()
                    } catch (_: Exception) {}
                }
                markersMap.clear()
                result.success(true)
            }
            "showCurrentLocation" -> {
                olaMap?.showCurrentLocation()
                result.success(true)
            }
            "hideCurrentLocation" -> {
                olaMap?.hideCurrentLocation()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun createPinBitmap(hexColor: String): Bitmap {
        val size = 64
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val parsedColor = try {
            Color.parseColor(hexColor)
        } catch (_: Exception) {
            Color.parseColor("#2ECC71")
        }

        val paintWhite = Paint().apply {
            color = Color.WHITE
            isAntiAlias = true
        }

        val paintFill = Paint().apply {
            color = parsedColor
            isAntiAlias = true
        }

        val cx = size / 2f
        val cy = size / 2f

        // Outer white border
        canvas.drawCircle(cx, cy, 26f, paintWhite)
        // Main colored circle
        canvas.drawCircle(cx, cy, 22f, paintFill)
        // Center white dot
        canvas.drawCircle(cx, cy, 8f, paintWhite)

        return bitmap
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        markersMap.clear()
    }
}
