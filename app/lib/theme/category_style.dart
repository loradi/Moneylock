import 'package:flutter/material.dart';

IconData categoryIcon(String category) => switch (category) {
      'Coffee & Dining' => Icons.local_cafe_outlined,
      'Groceries' => Icons.storefront_outlined,
      'Transport' => Icons.directions_car_outlined,
      'Entertainment' => Icons.movie_outlined,
      'Shopping & E-commerce' => Icons.shopping_bag_outlined,
      'Bills & Utilities' => Icons.receipt_long_outlined,
      'Health' => Icons.health_and_safety_outlined,
      'Tech' => Icons.devices_outlined,
      'Travel' => Icons.flight_outlined,
      _ => Icons.category_outlined,
    };

Color categoryContainerColor(String category) => switch (category) {
      'Groceries' => const Color(0xFFDCEFFF),
      'Transport' => const Color(0xFFFFDAD6),
      'Entertainment' => const Color(0xFFFFF2CC),
      'Shopping & E-commerce' => const Color(0xFFE5E2E1),
      'Bills & Utilities' => const Color(0xFFE3F2FD),
      'Health' => const Color(0xFFFCE4EC),
      'Tech' => const Color(0xFFEDE7F6),
      'Travel' => const Color(0xFFE0F7FA),
      _ => const Color(0xFFF4F4F5),
    };
