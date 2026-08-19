import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'user_avatar.dart';

/// Eine Zeile mit Avatar, Name und Freundescode - verwendet für
/// Freundesliste, eingehende/ausgehende Anfragen und die Suchvorschau.
class FriendListTile extends StatelessWidget {
  const FriendListTile({
    super.key,
    required this.name,
    required this.friendCode,
    this.profilePicture,
    this.trailing,
  });

  final String name;
  final String friendCode;
  final String? profilePicture;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          UserAvatar(name: name, profilePicture: profilePicture, radius: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  friendCode,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
