package `in`.adithyen.nivara

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
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
                val type = call.argument<String>("type") ?: "default"
                val label = call.argument<String>("label") ?: ""

                try {
                    // Remove existing marker with same id
                    markersMap[id]?.removeMarker()

                    val bitmap = createPinBitmap(hexColor, type, label)
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

    private fun createPinBitmap(hexColor: String, type: String = "default", label: String = ""): Bitmap {
        val parsedColor = try {
            Color.parseColor(hexColor)
        } catch (_: Exception) {
            Color.parseColor("#2ECC71")
        }

        // Conventional Dropped Location Pin (Teardrop shape with sharp needle point)
        if (type == "dropped_pin" || type == "pin") {
            val width = 80
            val height = 104
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val headRadius = 26f
            val headCenterY = 32f
            val headCenterX = 40f
            val needleTipY = 96f

            // Shadow under the needle tip
            val shadowPaint = Paint().apply {
                color = Color.argb(100, 0, 0, 0)
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawOval(
                RectF(headCenterX - 18f, needleTipY - 6f, headCenterX + 18f, needleTipY + 6f),
                shadowPaint
            )

            // Teardrop path
            val path = Path().apply {
                arcTo(
                    RectF(headCenterX - headRadius, headCenterY - headRadius, headCenterX + headRadius, headCenterY + headRadius),
                    -205f,
                    230f,
                    false
                )
                lineTo(headCenterX, needleTipY)
                close()
            }

            // Outer white border
            val strokePaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                style = Paint.Style.STROKE
                strokeWidth = 6f
                strokeJoin = Paint.Join.ROUND
                strokeCap = Paint.Cap.ROUND
            }
            canvas.drawPath(path, strokePaint)

            // Main vibrant color fill
            val fillPaint = Paint().apply {
                color = parsedColor
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawPath(path, fillPaint)

            // Inner white ring / target core
            val innerWhite = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawCircle(headCenterX, headCenterY, 11f, innerWhite)

            // Inner pin core center dot
            val centerDot = Paint().apply {
                color = parsedColor
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawCircle(headCenterX, headCenterY, 5f, centerDot)

            return bitmap
        }

        // Citizen Issue Report Pin (Teardrop pin in status color with alert badge)
        if (type == "report") {
            val width = 74
            val height = 94
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val headRadius = 24f
            val headCenterY = 28f
            val headCenterX = 37f
            val needleTipY = 88f

            // Shadow
            val shadowPaint = Paint().apply {
                color = Color.argb(80, 0, 0, 0)
                isAntiAlias = true
            }
            canvas.drawOval(
                RectF(headCenterX - 14f, needleTipY - 5f, headCenterX + 14f, needleTipY + 5f),
                shadowPaint
            )

            // Teardrop path
            val path = Path().apply {
                arcTo(
                    RectF(headCenterX - headRadius, headCenterY - headRadius, headCenterX + headRadius, headCenterY + headRadius),
                    -205f,
                    230f,
                    false
                )
                lineTo(headCenterX, needleTipY)
                close()
            }

            // White border
            val strokePaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                style = Paint.Style.STROKE
                strokeWidth = 5f
            }
            canvas.drawPath(path, strokePaint)

            // Status color fill
            val fillPaint = Paint().apply {
                color = parsedColor
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawPath(path, fillPaint)

            // White badge circle in center
            val badgePaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawCircle(headCenterX, headCenterY, 12f, badgePaint)

            // Exclamation / status symbol in center
            val textPaint = Paint().apply {
                color = parsedColor
                isAntiAlias = true
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText("!", headCenterX, headCenterY + 7f, textPaint)

            return bitmap
        }

        // Lost Item Marker (Diamond / Amber badge with 'L' or search glyph)
        if (type == "lost") {
            val width = 76
            val height = 90
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val cx = 38f
            val cy = 34f

            // Shadow
            val shadowPaint = Paint().apply {
                color = Color.argb(80, 0, 0, 0)
                isAntiAlias = true
            }
            canvas.drawOval(RectF(cx - 16f, 80f, cx + 16f, 88f), shadowPaint)

            // Diamond / shield pointer path
            val path = Path().apply {
                moveTo(cx, 84f)
                lineTo(cx - 26f, cy + 4f)
                lineTo(cx - 26f, cy - 18f)
                quadTo(cx - 26f, cy - 30f, cx - 14f, cy - 30f)
                lineTo(cx + 14f, cy - 30f)
                quadTo(cx + 26f, cy - 30f, cx + 26f, cy - 18f)
                lineTo(cx + 26f, cy + 4f)
                close()
            }

            // White stroke
            val strokePaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                style = Paint.Style.STROKE
                strokeWidth = 5f
            }
            canvas.drawPath(path, strokePaint)

            // Fill (Coral / Amber #FF6D00)
            val fillPaint = Paint().apply {
                color = parsedColor
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawPath(path, fillPaint)

            // Badge text "LOST"
            val textPaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText("LOST", cx, cy - 2f, textPaint)

            return bitmap
        }

        // Found Item Marker (Rounded Blue / Cyan Shield with 'FOUND')
        if (type == "found") {
            val width = 76
            val height = 90
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val cx = 38f
            val cy = 34f

            // Shadow
            val shadowPaint = Paint().apply {
                color = Color.argb(80, 0, 0, 0)
                isAntiAlias = true
            }
            canvas.drawOval(RectF(cx - 16f, 80f, cx + 16f, 88f), shadowPaint)

            // Shield pointer path
            val path = Path().apply {
                moveTo(cx, 84f)
                lineTo(cx - 28f, cy + 6f)
                lineTo(cx - 28f, cy - 20f)
                quadTo(cx - 28f, cy - 30f, cx - 16f, cy - 30f)
                lineTo(cx + 16f, cy - 30f)
                quadTo(cx + 28f, cy - 30f, cx + 28f, cy - 20f)
                lineTo(cx + 28f, cy + 6f)
                close()
            }

            // White stroke
            val strokePaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                style = Paint.Style.STROKE
                strokeWidth = 5f
            }
            canvas.drawPath(path, strokePaint)

            // Fill (Cyan / Blue #00B0FF)
            val fillPaint = Paint().apply {
                color = parsedColor
                isAntiAlias = true
                style = Paint.Style.FILL
            }
            canvas.drawPath(path, fillPaint)

            // Badge text "FOUND"
            val textPaint = Paint().apply {
                color = Color.WHITE
                isAntiAlias = true
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText("FOUND", cx, cy - 2f, textPaint)

            return bitmap
        }

        // Generic / POI circular pin
        val size = 70
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

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
        canvas.drawCircle(cx, cy, 28f, paintWhite)
        // Main colored circle
        canvas.drawCircle(cx, cy, 24f, paintFill)
        // Center white dot
        canvas.drawCircle(cx, cy, 10f, paintWhite)

        return bitmap
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        markersMap.clear()
    }
}
