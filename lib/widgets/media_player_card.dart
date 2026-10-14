import 'package:flutter/material.dart';

/// Карточка медиаплеера на главном экране.
///
/// Это демонстрационное состояние (play/pause переключается локально).
/// Для реальной интеграции с музыкой подключите пакет `audio_service`
/// и слушайте активную MediaSession системы — тогда здесь будут
/// настоящие трек/исполнитель/обложка и управление воспроизведением.
class MediaPlayerCard extends StatefulWidget {
  const MediaPlayerCard({super.key});

  @override
  State<MediaPlayerCard> createState() => _MediaPlayerCardState();
}

class _MediaPlayerCardState extends State<MediaPlayerCard> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _playing ? 'Радио FM 101.2' : 'Ничего не играет',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _playing ? 'Прямой эфир' : 'Выберите пресет ниже',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: () => setState(() => _playing = !_playing),
              icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
