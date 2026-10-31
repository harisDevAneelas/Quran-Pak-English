import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../profile.dart';

/// Horizontal profile chips for editing another profile's prefs without
/// switching the app's active profile. Chips start from the RTL leading edge.
class ProfileEditChips extends StatelessWidget {
  const ProfileEditChips({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
    this.onCreateNew,
    this.enabled = true,
  });

  final List<Profile> profiles;
  final String? selectedId;
  final ValueChanged<Profile> onSelected;

  /// Optional leading chip to create a profile without switching the app.
  final VoidCallback? onCreateNew;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty && onCreateNew == null) {
      return const SizedBox.shrink();
    }
    final ink = Theme.of(context).colorScheme.onSurface;
    final createSlot = onCreateNew != null ? 1 : 0;

    return SizedBox(
      height: 40,
      width: double.infinity,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: profiles.length + createSlot,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (createSlot == 1 && index == 0) {
            return _CreateChip(
              enabled: enabled,
              onTap: onCreateNew!,
            );
          }
          final profile = profiles[index - createSlot];
          final isActive = profile.id == selectedId;
          return Material(
            color: isActive ? AppTheme.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: enabled ? () => onSelected(profile) : null,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppTheme.orange, width: 1.1),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive) ...[
                        const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive ? Colors.white : ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreateChip extends StatelessWidget {
  const _CreateChip({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.orange, width: 1.1),
          ),
          child: const Center(
            child: Icon(Icons.add, size: 20, color: AppTheme.orange),
          ),
        ),
      ),
    );
  }
}
