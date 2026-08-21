import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

class BrandIcon {
  final Color color;
  final IconData icon;
  const BrandIcon(this.color, this.icon);
}

/// Real brand-logo silhouettes from the `simple_icons` package (CC0-licensed
/// SVG artwork; the brand names/logos themselves remain trademarks of their
/// owners -- used here only to identify which service a subscription is
/// for, the same way Mint/Copilot/Rocket Money and similar apps do).
///
/// A handful of brands (Disney+, Amazon, Hulu, Xbox, Adobe, OpenAI/ChatGPT)
/// were removed from simple_icons entirely following legal takedown
/// requests and have no icon in the installed package at all -- those keep
/// their original hand-picked Material glyph + brand color as a fallback.
final brandIcons = <String, BrandIcon>{
  'netflix': BrandIcon(SimpleIconColors.netflix, SimpleIcons.netflix),
  'spotify': BrandIcon(SimpleIconColors.spotify, SimpleIcons.spotify),
  // Disney+ icon was removed from simple_icons after a legal takedown
  // request; no substitute exists in the package, so this keeps the
  // original Material fallback glyph and color.
  'disney_plus': const BrandIcon(Color(0xFF113CCF), Icons.castle),
  // No "youtubepremium" variant exists in the package; the plain YouTube
  // mark is the closest available icon.
  'youtube_premium': BrandIcon(SimpleIconColors.youtube, SimpleIcons.youtube),
  // Amazon icon (and any AWS/Prime variant) was removed from simple_icons
  // after a legal takedown request; no substitute exists in the package.
  'amazon_prime': const BrandIcon(Color(0xFF00A8E1), Icons.shopping_bag),
  'apple_music': BrandIcon(SimpleIconColors.applemusic, SimpleIcons.applemusic),
  // No "appletvplus" variant exists; the plain Apple TV mark is the
  // closest available icon.
  'apple_tv_plus': BrandIcon(SimpleIconColors.appletv, SimpleIcons.appletv),
  // simple_icons ships "hbomax" (the current Max rebrand identifier, not
  // "hbo"), which is a closer match to this key's intent than the old HBO
  // mark; kept the existing 'hbo_max' map key for backward compatibility.
  'hbo_max': BrandIcon(SimpleIconColors.hbomax, SimpleIcons.hbomax),
  'icloud_plus': BrandIcon(SimpleIconColors.icloud, SimpleIcons.icloud),
  // Hulu icon was removed from simple_icons after a legal takedown
  // request; no substitute exists in the package.
  'hulu': const BrandIcon(Color(0xFF1CE783), Icons.live_tv),
  // No "playstationplus" variant exists; the plain PlayStation mark is the
  // closest available icon.
  'playstation_plus':
      BrandIcon(SimpleIconColors.playstation, SimpleIcons.playstation),
  // Xbox icon was removed from simple_icons after a legal takedown
  // request; no substitute exists in the package.
  'xbox_game_pass': const BrandIcon(Color(0xFF107C10), Icons.videogame_asset),
  // Adobe (and Creative Cloud) icons were removed from simple_icons after
  // a legal takedown request; no substitute exists in the package.
  'adobe_creative_cloud': const BrandIcon(Color(0xFFDA1F26), Icons.brush),
  'dropbox': BrandIcon(SimpleIconColors.dropbox, SimpleIcons.dropbox),
  // The package slugifies "1Password" as "n1password" (names starting with
  // a digit get an "n" prefix), not "onepassword".
  'onepassword': BrandIcon(SimpleIconColors.n1password, SimpleIcons.n1password),
  // OpenAI/ChatGPT icon was removed from simple_icons after a legal
  // takedown request; only an unrelated "openaigym" mark remains, so this
  // keeps the original Material fallback glyph and color.
  'chatgpt_plus': const BrandIcon(Color(0xFF10A37F), Icons.chat_bubble),
  'notion': BrandIcon(SimpleIconColors.notion, SimpleIcons.notion),
};

Color _colorForName(String name) {
  const palette = [
    Color(0xFFBA1A1A),
    Color(0xFF6750A4),
    Color(0xFF006A6A),
    Color(0xFF7D5260),
    Color(0xFF386A20),
    Color(0xFF984061),
  ];
  return palette[name.codeUnits.fold(0, (a, b) => a + b) % palette.length];
}

class SubscriptionAvatar extends StatelessWidget {
  final String? brandKey;
  final String name;
  const SubscriptionAvatar({super.key, this.brandKey, required this.name});

  @override
  Widget build(BuildContext context) {
    final brand = brandKey == null ? null : brandIcons[brandKey];
    if (brand != null) {
      return CircleAvatar(
        backgroundColor: brand.color,
        child: Icon(brand.icon, color: Colors.white),
      );
    }
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: _colorForName(name),
      child: Text(initial, style: const TextStyle(color: Colors.white)),
    );
  }
}
