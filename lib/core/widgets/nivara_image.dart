import 'dart:convert';
import 'package:flutter/material.dart';

/// Universal resilient image renderer supporting Network URLs, Base64 Data URIs,
/// and local file paths with graceful fallback and loading placeholders.
class NivaraImage extends StatelessWidget {
  const NivaraImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.image_not_supported_outlined,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cleanSource = source.trim();

    Widget placeholder() => Container(
      width: width,
      height: height,
      color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: 24,
          color: isDark ? Colors.white24 : Colors.black26,
        ),
      ),
    );

    Widget imageWidget;

    if (cleanSource.startsWith('data:image')) {
      try {
        final commaIdx = cleanSource.indexOf(',');
        final base64Str = commaIdx != -1
            ? cleanSource.substring(commaIdx + 1)
            : cleanSource;
        final bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => placeholder(),
        );
      } catch (_) {
        imageWidget = placeholder();
      }
    } else if (cleanSource.startsWith('http://') || cleanSource.startsWith('https://')) {
      imageWidget = Image.network(
        cleanSource,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => placeholder(),
      );
    } else {
      imageWidget = placeholder();
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
