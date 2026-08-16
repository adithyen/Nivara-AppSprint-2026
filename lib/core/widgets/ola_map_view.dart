import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../constants.dart';
import '../services/ola_maps_service.dart';

/// Callback when the native Ola Map is fully ready and loaded.
typedef OnOlaMapReadyCallback = void Function(OlaNativeMapController controller);

/// Callback when a marker is clicked on the Ola Map.
typedef OnOlaMarkerClickedCallback = void Function(String markerId);

/// Callback when user taps a point on the Ola Map.
typedef OnOlaMapClickedCallback = void Function(double lat, double lng);

/// Callback when the Ola Map camera becomes idle.
typedef OnOlaCameraIdleCallback = void Function(double? lat, double? lng);

/// Controller to interact with the embedded native [OlaMapView].
class OlaNativeMapController {
  OlaNativeMapController._(this._channel, this.viewId);

  final MethodChannel _channel;
  final int viewId;

  Future<void> animateCamera({
    required double lat,
    required double lng,
    double zoom = 15.0,
  }) async {
    try {
      await _channel.invokeMethod('animateCamera', {
        'lat': lat,
        'lng': lng,
        'zoom': zoom,
      });
    } catch (_) {}
  }

  Future<void> addMarker({
    required String id,
    required double lat,
    required double lng,
    String? snippet,
    Color color = const Color(0xFF2ECC71),
  }) async {
    try {
      final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      await _channel.invokeMethod('addMarker', {
        'id': id,
        'lat': lat,
        'lng': lng,
        'snippet': snippet ?? '',
        'color': hex,
      });
    } catch (_) {}
  }

  Future<void> removeMarker(String id) async {
    try {
      await _channel.invokeMethod('removeMarker', {'id': id});
    } catch (_) {}
  }

  Future<void> setStyleUrl(String styleUrl) async {
    try {
      await _channel.invokeMethod('setStyleUrl', {'styleUrl': styleUrl});
    } catch (_) {}
  }

  Future<void> clearMarkers() async {
    try {
      await _channel.invokeMethod('clearMarkers');
    } catch (_) {}
  }

  Future<void> showCurrentLocation() async {
    try {
      await _channel.invokeMethod('showCurrentLocation');
    } catch (_) {}
  }

  Future<void> hideCurrentLocation() async {
    try {
      await _channel.invokeMethod('hideCurrentLocation');
    } catch (_) {}
  }
}

/// Flutter widget that renders the official native Android [OlaMapView] SDK
/// (`com.ola.mapsdk.view.OlaMapView`) via Flutter PlatformView.
class OlaNativeMapWidget extends StatefulWidget {
  const OlaNativeMapWidget({
    super.key,
    this.initialLat = kDefaultLat,
    this.initialLng = kDefaultLng,
    this.initialZoom = 15.0,
    this.styleUrl,
    this.onMapReady,
    this.onMarkerClicked,
    this.onMapClicked,
    this.onCameraIdle,
    this.onMapError,
  });

  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final String? styleUrl;
  final OnOlaMapReadyCallback? onMapReady;
  final OnOlaMarkerClickedCallback? onMarkerClicked;
  final OnOlaMapClickedCallback? onMapClicked;
  final OnOlaCameraIdleCallback? onCameraIdle;
  final ValueChanged<String>? onMapError;

  @override
  State<OlaNativeMapWidget> createState() => _OlaNativeMapWidgetState();
}

class _OlaNativeMapWidgetState extends State<OlaNativeMapWidget> {
  OlaNativeMapController? _controller;
  String? _lastAppliedStyle;

  String get _apiKey =>
      dotenv.env['OLA_MAPS_API_KEY']?.trim() ?? '';

  String _resolveEffectiveStyle(BuildContext context) {
    if (widget.styleUrl != null && widget.styleUrl!.isNotEmpty) {
      return widget.styleUrl!;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OlaMapsService.instance.getStyleUrl(isDark: isDark);
  }

  @override
  void didUpdateWidget(covariant OlaNativeMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newStyle = _resolveEffectiveStyle(context);
    if (_lastAppliedStyle != null && _lastAppliedStyle != newStyle) {
      _lastAppliedStyle = newStyle;
      _controller?.setStyleUrl(newStyle);
    }
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('com.nivara.ola_map_$id');
    final controller = OlaNativeMapController._(channel, id);
    _controller = controller;

    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMapReady':
          widget.onMapReady?.call(controller);
          break;
        case 'onMarkerClicked':
          final markerId = (call.arguments as Map?)?['markerId'] as String?;
          if (markerId != null) {
            widget.onMarkerClicked?.call(markerId);
          }
          break;
        case 'onMapClicked':
          final args = call.arguments as Map?;
          final lat = (args?['lat'] as num?)?.toDouble();
          final lng = (args?['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            widget.onMapClicked?.call(lat, lng);
          }
          break;
        case 'onCameraIdle':
          final args = call.arguments as Map?;
          final lat = (args?['lat'] as num?)?.toDouble();
          final lng = (args?['lng'] as num?)?.toDouble();
          widget.onCameraIdle?.call(lat, lng);
          break;
        case 'onMapError':
          final error = call.arguments as String? ?? 'Map service error';
          widget.onMapError?.call(error);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Container(
        color: isDark ? const Color(0xFF0B0F14) : const Color(0xFFF1F5F9),
        child: Center(
          child: Text(
            'Map view is optimized for Android',
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
            ),
          ),
        ),
      );
    }

    final effectiveStyleUrl = _resolveEffectiveStyle(context);
    _lastAppliedStyle = effectiveStyleUrl;

    final creationParams = <String, dynamic>{
      'apiKey': _apiKey,
      'initialLat': widget.initialLat,
      'initialLng': widget.initialLng,
      'initialZoom': widget.initialZoom,
      'styleUrl': effectiveStyleUrl,
    };

    return PlatformViewLink(
      viewType: 'ola_native_map_view',
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              EagerGestureRecognizer.new,
            ),
          },
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        return PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: 'ola_native_map_view',
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () {
            params.onFocusChanged(true);
          },
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
          ..create();
      },
    );
  }
}
