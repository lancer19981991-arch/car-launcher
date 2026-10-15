import 'package:flutter/material.dart';

/// Что показать в одной плитке пресета.
class PresetTileData {
  const PresetTileData({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.onLongPress,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
}

/// Сетка пресетов на главном экране.
class PresetGrid extends StatelessWidget {
  const PresetGrid({super.key, required this.tiles});

  final List<PresetTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) => _PresetTile(data: tiles[index]),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.data});

  final PresetTileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        onLongPress: data.onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 40, height: 40, child: Center(child: data.icon)),
              const SizedBox(height: 8),
              Text(
                data.title,
                style: theme.textTheme.labelMedium,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (data.subtitle != null)
                Text(
                  data.subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
