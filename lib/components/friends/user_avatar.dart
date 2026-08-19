import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Avatar für Profil-/Freundes-Darstellungen. Zeigt das echte Profilbild,
/// sofern vorhanden - andernfalls die Initialen des Namens als neutrale
/// Darstellung für "kein Profilbild vorhanden" (keine Fake-Bilddaten).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.profilePicture,
    this.radius = 28,
  });

  final String name;
  final String? profilePicture;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final picture = profilePicture;
    if (picture != null && picture.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: NetworkImage(picture),
      );
    }

    final initials = _initialsFor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfaceVariant,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }

  String _initialsFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.first.substring(0, 1);
    final last = parts.length > 1 ? parts.last.substring(0, 1) : '';
    return (first + last).toUpperCase();
  }
}
