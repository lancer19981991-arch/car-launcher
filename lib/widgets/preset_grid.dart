import 'package:flutter/material.dart';

import '../models/preset.dart';

/// Сетка быстрых ярлыков (пресетов) на главном экране.
class PresetGrid extends StatelessWidget {
  const PresetGrid({super.key, required this.presets});

  final List<CarPreset> presets;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: presets.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final preset = presets[index];
        return _PresetTile(preset: preset);
      },
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset});

  final CarPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: preset.action,
        child: Card(
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(preset.icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  preset.title,
                  style: theme.textTheme.labelMedium,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
