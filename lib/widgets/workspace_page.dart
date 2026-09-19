import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../providers/workspace_providers.dart';
import '../strings.dart';
import 'document_pane.dart';
import 'file_manager_pane.dart';
import 'split_view.dart';
import 'stamp_preview_pane.dart';

class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  Timer? _statusTimer;

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _scheduleStatusClear() {
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      ref.read(statusMessageProvider.notifier).state = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(pythonEngineAvailableProvider);
    final status = ref.watch(statusMessageProvider);
    final session = ref.watch(documentSessionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final canSave = session != null && session.busyMessage == null;

    ref.listen<String?>(statusMessageProvider, (previous, next) {
      if (next != null && next != previous) {
        _scheduleStatusClear();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.appTitle),
        actions: [
          IconButton(
            tooltip: themeMode == ThemeMode.dark ? S.lightTheme : S.darkTheme,
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
            child: FilledButton.icon(
              onPressed: canSave
                  ? () => ref.read(documentSessionProvider.notifier).saveAs()
                  : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text(S.savePdf),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          engine.maybeWhen(
            data: (available) {
              if (available) {
                return const SizedBox.shrink();
              }
              return MaterialBanner(
                content: const Text(S.engineMissing),
                actions: [
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(pythonEngineAvailableProvider),
                    child: const Text('Перевірити знову'),
                  ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const Expanded(
            child: ThreePaneSplit(
              left: FileManagerPane(),
              middle: StampPreviewPane(),
              right: DocumentPane(),
            ),
          ),
          if (status != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.3,
                child: Material(
                  color: const Color(0xFFE8E8E8),
                  // macOS window corner radius (~10pt)
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            status,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF333333)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          color: const Color(0xFF333333),
                          onPressed: () {
                            _statusTimer?.cancel();
                            ref.read(statusMessageProvider.notifier).state =
                                null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
