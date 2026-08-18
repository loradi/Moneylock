import 'package:flutter/material.dart';

class BrandIcon {
  final Color color;
  final IconData icon;
  const BrandIcon(this.color, this.icon);
}

/// Simplified, hand-drawn vector representations (color + a recognizable
/// glyph) for common subscription services -- not reproductions of the
/// official logos.
const brandIcons = <String, BrandIcon>{
  'netflix': BrandIcon(Color(0xFFE50914), Icons.play_arrow),
  'spotify': BrandIcon(Color(0xFF1DB954), Icons.graphic_eq),
  'disney_plus': BrandIcon(Color(0xFF113CCF), Icons.castle),
  'youtube_premium': BrandIcon(Color(0xFFFF0000), Icons.smart_display),
  'amazon_prime': BrandIcon(Color(0xFF00A8E1), Icons.shopping_bag),
  'apple_music': BrandIcon(Color(0xFFFA243C), Icons.music_note),
  'apple_tv_plus': BrandIcon(Color(0xFF000000), Icons.tv),
  'hbo_max': BrandIcon(Color(0xFF5822B4), Icons.theaters),
  'icloud_plus': BrandIcon(Color(0xFF3693F3), Icons.cloud),
  'hulu': BrandIcon(Color(0xFF1CE783), Icons.live_tv),
  'playstation_plus': BrandIcon(Color(0xFF0070D1), Icons.sports_esports),
  'xbox_game_pass': BrandIcon(Color(0xFF107C10), Icons.videogame_asset),
  'adobe_creative_cloud': BrandIcon(Color(0xFFDA1F26), Icons.brush),
  'dropbox': BrandIcon(Color(0xFF0061FF), Icons.folder),
  'onepassword': BrandIcon(Color(0xFF1A8CFF), Icons.key),
  'chatgpt_plus': BrandIcon(Color(0xFF10A37F), Icons.chat_bubble),
  'notion': BrandIcon(Color(0xFF000000), Icons.description),
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
