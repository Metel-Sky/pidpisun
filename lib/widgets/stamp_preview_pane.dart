import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/workspace_providers.dart';
import '../stamp_ink.dart';
import '../strings.dart';
import 'stamp_import.dart';

class StampPreviewPane extends ConsumerWidget {
  const StampPreviewPane({super.key});

  static const previewBackground = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(activeStampPathProvider);
    final theme = Theme.of(context);

    return DropTarget(
      onDragDone: (details) => importPngsFromDrop(
        ref,
        details.files.map((file) => file.path),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text('Підпис / печатка', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ColoredBox(
                color: previewBackground,
                child: path == null
                    ? Center(
                        child: Text(
                          S.pickStamp,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5F5F5F),
                          ),
                        ),
                      )
                    : _StampPreview(path: path),
              ),
            ),
          ),
          if (path != null) const _StampControls(),
        ],
      ),
    );
  }
}

class _StampPreview extends ConsumerWidget {
  const _StampPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(documentSessionProvider);
    final selected = session?.stamps
        .where((stamp) => stamp.id == session.selectedStampId)
        .firstOrNull;
    final fallback = ref.watch(defaultStampOpacityProvider);
    final fallbackColor = ref.watch(defaultStampColorProvider);
    final opacity = (selected?.opacity ?? fallback).clamp(0.15, 1.0);
    final color = selected?.color ?? fallbackColor;

    return Draggable<String>(
      data: path,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        ref.read(draggingStampPathProvider.notifier).state = path;
      },
      onDragEnd: (_) {
        ref.read(draggingStampPathProvider.notifier).state = null;
      },
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 140,
          height: 90,
          child: Opacity(
            opacity: opacity,
            child: StampImage(
              path: path,
              color: color,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Opacity(
            opacity: opacity,
            child: StampImage(
              path: path,
              color: color,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

class _StampControls extends ConsumerWidget {
  const _StampControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(documentSessionProvider);
    final selected = session?.stamps
        .where((stamp) => stamp.id == session.selectedStampId)
        .firstOrNull;
    final fallback = ref.watch(defaultStampOpacityProvider);
    final fallbackColor = ref.watch(defaultStampColorProvider);
    final opacity = (selected?.opacity ?? fallback).clamp(0.15, 1.0);
    final color = selected?.color ?? fallbackColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.opacity,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  value: opacity,
                  min: 0.15,
                  max: 1,
                  onChanged: (value) {
                    ref.read(defaultStampOpacityProvider.notifier).state = value;
                    if (selected != null) {
                      ref
                          .read(documentSessionProvider.notifier)
                          .setSelectedOpacity(value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(opacity * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
          Text(S.opacity, style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(S.color, style: theme.textTheme.labelSmall),
          ),
          const SizedBox(height: 6),
          StampColorPalette(
            selected: color,
            onChanged: (value) {
              ref.read(defaultStampColorProvider.notifier).state = value;
              if (selected != null) {
                ref.read(documentSessionProvider.notifier).setSelectedColor(value);
              }
            },
          ),
          const SizedBox(height: 8),
          const Text(S.stampHint, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
