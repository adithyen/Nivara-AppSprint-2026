import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/enums.dart';

/// One place for everything about a Lost & Found contact method: the icon and
/// colour it shows with, the labels/hints/keyboard the form needs, how the
/// value reads on the viewer's side, and the one-tap deep link that actually
/// reaches the person.
///
/// Deep links: phone → `tel:`, whatsapp → `wa.me/<digits>`, email → `mailto:`,
/// telegram → `t.me/<handle>`, instagram → `instagram.com/<handle>`.

IconData lfContactIcon(LFContactMethod m) => switch (m) {
  LFContactMethod.phone => Icons.call,
  LFContactMethod.whatsapp => Icons.chat,
  LFContactMethod.email => Icons.email_outlined,
  LFContactMethod.telegram => Icons.send,
  LFContactMethod.instagram => Icons.camera_alt_outlined,
};

Color lfContactColor(LFContactMethod m) => switch (m) {
  LFContactMethod.phone => NivaraColors.primary,
  LFContactMethod.whatsapp => const Color(0xFF25D366),
  LFContactMethod.email => NivaraColors.accent,
  LFContactMethod.telegram => const Color(0xFF229ED9),
  LFContactMethod.instagram => const Color(0xFFC13584),
};

/// Verb for the action button ("Call", "WhatsApp", …).
String lfContactActionLabel(LFContactMethod m) => switch (m) {
  LFContactMethod.phone => 'Call',
  LFContactMethod.whatsapp => 'WhatsApp',
  LFContactMethod.email => 'Email',
  LFContactMethod.telegram => 'Open Telegram',
  LFContactMethod.instagram => 'Open Instagram',
};

// ── Form-side helpers ───────────────────────────────────────────────────────

String lfContactFieldLabel(LFContactMethod m) => switch (m) {
  LFContactMethod.phone => 'Phone number',
  LFContactMethod.whatsapp => 'WhatsApp number',
  LFContactMethod.email => 'Email address',
  LFContactMethod.telegram => 'Telegram username',
  LFContactMethod.instagram => 'Instagram username',
};

String lfContactHint(LFContactMethod m) => switch (m) {
  LFContactMethod.phone => '+91 98765 43210',
  LFContactMethod.whatsapp => '+91 98765 43210 (with country code)',
  LFContactMethod.email => 'you@example.com',
  LFContactMethod.telegram => '@username',
  LFContactMethod.instagram => '@username',
};

TextInputType lfContactKeyboard(LFContactMethod m) => switch (m) {
  LFContactMethod.phone || LFContactMethod.whatsapp => TextInputType.phone,
  LFContactMethod.email => TextInputType.emailAddress,
  LFContactMethod.telegram || LFContactMethod.instagram => TextInputType.text,
};

/// Returns an error message if [value] isn't usable for [m], else null.
String? lfContactValidate(LFContactMethod m, String value) {
  final v = value.trim();
  if (v.isEmpty) {
    return 'Please enter your ${lfContactFieldLabel(m).toLowerCase()}.';
  }
  switch (m) {
    case LFContactMethod.phone:
    case LFContactMethod.whatsapp:
      if (_digits(v).length < 7) return 'Enter a valid phone number.';
    case LFContactMethod.email:
      if (!v.contains('@') || !v.contains('.')) {
        return 'Enter a valid email address.';
      }
    case LFContactMethod.telegram:
    case LFContactMethod.instagram:
      if (_handle(v).isEmpty) return 'Enter a valid username.';
  }
  return null;
}

// ── Viewer-side ─────────────────────────────────────────────────────────────

/// How the contact string should read to someone viewing the item.
String lfContactDisplay(LFContactMethod m, String value) {
  final v = value.trim();
  return switch (m) {
    LFContactMethod.telegram || LFContactMethod.instagram => '@${_handle(v)}',
    _ => v,
  };
}

/// The deep link for a one-tap contact, or null if [value] is empty.
Uri? lfContactUri(LFContactMethod m, String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  return switch (m) {
    LFContactMethod.phone => Uri(scheme: 'tel', path: _tel(v)),
    LFContactMethod.whatsapp => Uri.parse('https://wa.me/${_digits(v)}'),
    LFContactMethod.email => Uri(scheme: 'mailto', path: v),
    LFContactMethod.telegram => Uri.parse('https://t.me/${_handle(v)}'),
    LFContactMethod.instagram => Uri.parse(
      'https://instagram.com/${_handle(v)}',
    ),
  };
}

/// Launches the contact deep link in the relevant external app. Returns false
/// if there's nothing to launch or the platform refused.
Future<bool> launchLFContact(LFContactMethod m, String value) async {
  final uri = lfContactUri(m, value);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

// ── Normalisers ─────────────────────────────────────────────────────────────

/// Digits only — for wa.me, which wants a country-coded number with no symbols.
String _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

/// Keep a leading + and digits — a dialable `tel:` target.
String _tel(String v) => v.replaceAll(RegExp(r'[^0-9+]'), '');

/// A bare @handle: strip a pasted profile URL to its last segment, drop '@'.
String _handle(String v) {
  var s = v.trim();
  final slash = s.lastIndexOf('/');
  if (slash != -1 && slash < s.length - 1) s = s.substring(slash + 1);
  return s.replaceAll('@', '').trim();
}
