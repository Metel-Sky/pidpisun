import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../providers/workspace_providers.dart';
import '../services/file_browser_service.dart';
import '../services/portable_store.dart';
import '../services/stamp_vault.dart';
import '../stamp_ink.dart';
import '../strings.dart';
import 'stamp_import.dart';

class FileManagerPane extends ConsumerWidget {
  const FileManagerPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDir = ref.watch(currentDirectoryProvider);
    final listing = ref.watch(directoryListingProvider);
    final pinned = ref.watch(pinnedFoldersProvider);
    final activeStamp = ref.watch(activeStampPathProvider);
    final theme = Theme.of(context);

    return DropTarget(
      onDragDone: (details) async {
        final paths = details.files.map((file) => file.path).toList();
        final inLibrary = PortableStore.isStampsDirectory(
          ref.read(currentDirectoryProvider),
        );
        if (inLibrary) {
          await importPngsFromDrop(ref, paths);
          return;
        }
        final png = paths.where(FileBrowserService.isPng).firstOrNull;
        if (png != null) {
          ref.read(activeStampPathProvider.notifier).state = png;
        }
        final document = paths.where(FileBrowserService.isDocument).firstOrNull;
        if (document != null) {
          await ref.read(documentSessionProvider.notifier).openPath(document);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: S.up,
                  onPressed: PortableStore.isStampsDirectory(currentDir)
                      ? null
                      : () =>
                            ref.read(currentDirectoryProvider.notifier).goUp(),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: S.openFolder,
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: S.openFolder,
                    );
                    if (path != null) {
                      ref.read(currentDirectoryProvider.notifier).open(path);
                    }
                  },
                  icon: const Icon(Icons.folder_open),
                ),
                IconButton(
                  tooltip: S.pinFolder,
                  onPressed: () {
                    ref.read(pinnedFoldersProvider.notifier).pin(currentDir);
                  },
                  icon: const Icon(Icons.push_pin_outlined),
                ),
                IconButton(
                  tooltip: S.addPngToLibrary,
                  onPressed: () async {
                    final picked = await FilePicker.platform.pickFiles(
                      dialogTitle: S.addPng,
                      type: FileType.custom,
                      allowedExtensions: const ['png'],
                      allowMultiple: true,
                      lockParentWindow: true,
                    );
                    if (picked == null) {
                      return;
                    }
                    await importPngsFromDrop(
                      ref,
                      picked.files
                          .map((file) => file.path)
                          .whereType<String>(),
                    );
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
              ],
            ),
          ),
          if (!PortableStore.isStampsDirectory(currentDir))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                currentDir,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(S.pinned, style: theme.textTheme.labelLarge),
          ),
          pinned.when(
            data: (folders) {
              if (folders.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text('Немає закріплених папок'),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final selected = p.equals(folder.path, currentDir);
                    return ListTile(
                      dense: true,
                      selected: selected,
                      leading: const Icon(Icons.folder, size: 20),
                      title: Text(
                        folder.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => ref
                          .read(currentDirectoryProvider.notifier)
                          .open(folder.path),
                      trailing: PortableStore.isStampsDirectory(folder.path)
                          ? null
                          : IconButton(
                              tooltip: S.unpin,
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => ref
                                  .read(pinnedFoldersProvider.notifier)
                                  .unpin(folder.path),
                            ),
                    );
                  },
                ),
              );
            },
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('$error'),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(S.files, style: theme.textTheme.labelLarge),
          ),
          Expanded(
            child: listing.when(
              data: (entries) {
                if (entries.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(S.dropPngHere, textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _FileRow(
                      key: ValueKey(entry.path),
                      entry: entry,
                      selected: activeStamp == entry.path,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({
    super.key,
    required this.entry,
    required this.selected,
  });

  final FileSystemEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inLibrary =
        !entry.isDirectory &&
        entry.kind == FileKind.png &&
        PortableStore.isStampsDirectory(p.dirname(entry.path));

    final row = ListTile(
      dense: true,
      selected: selected,
      leading: Icon(_iconFor(entry.kind), size: 20),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      onTap: () => _onTap(ref),
      onLongPress: inLibrary
          ? () => _showStampMenu(context, ref)
          : () => _onOpen(ref),
      trailing: inLibrary
          ? PopupMenuButton<String>(
              tooltip: 'Дії',
              onSelected: (value) {
                if (value == 'rename') {
                  _rename(context, ref);
                } else if (value == 'delete') {
                  _delete(context, ref);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text(S.renamePng)),
                PopupMenuItem(value: 'delete', child: Text(S.deletePng)),
              ],
            )
          : null,
    );

    if (entry.kind != FileKind.png) {
      return row;
    }

    return GestureDetector(
      onSecondaryTap: inLibrary ? () => _showStampMenu(context, ref) : null,
      child: Draggable<String>(
        data: entry.path,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () {
          ref.read(draggingStampPathProvider.notifier).state = entry.path;
          ref.read(activeStampPathProvider.notifier).state = entry.path;
        },
        onDragEnd: (_) {
          ref.read(draggingStampPathProvider.notifier).state = null;
        },
        feedback: _StampDragFeedback(path: entry.path),
        childWhenDragging: Opacity(opacity: 0.45, child: row),
        child: row,
      ),
    );
  }

  Future<void> _showStampMenu(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx + box.size.width - 8,
        origin.dy + 8,
        origin.dx + box.size.width,
        origin.dy,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text(S.renamePng)),
        PopupMenuItem(value: 'delete', child: Text(S.deletePng)),
      ],
    );
    if (!context.mounted) {
      return;
    }
    if (action == 'rename') {
      await _rename(context, ref);
    } else if (action == 'delete') {
      await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _RenamePngDialog(
        initialName: p.basenameWithoutExtension(entry.name),
      ),
    );
    if (next == null || !context.mounted) {
      return;
    }
    try {
      final renamed = PortableStore.renameStamp(entry.path, next);
      ref.read(stampLibraryEpochProvider.notifier).state++;
      if (ref.read(activeStampPathProvider) == entry.path) {
        ref.read(activeStampPathProvider.notifier).state = renamed;
      }
      if (ref.read(draggingStampPathProvider) == entry.path) {
        ref.read(draggingStampPathProvider.notifier).state = renamed;
      }
      ref.read(documentSessionProvider.notifier).retargetPng(entry.path, renamed);
      ref.read(statusMessageProvider.notifier).state = S.pngRenamed;
    } on StampVaultException catch (error) {
      ref.read(statusMessageProvider.notifier).state = error.message;
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(S.deletePngTitle),
          content: Text('Видалити «${entry.name}» з печаток?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Скасувати'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(S.deletePng),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      PortableStore.deleteStamp(entry.path);
      ref.read(stampLibraryEpochProvider.notifier).state++;
      if (ref.read(activeStampPathProvider) == entry.path) {
        final left = PortableStore.listStampEntries();
        ref.read(activeStampPathProvider.notifier).state =
            left.isEmpty ? null : left.first.path;
      }
      if (ref.read(draggingStampPathProvider) == entry.path) {
        ref.read(draggingStampPathProvider.notifier).state = null;
      }
      ref.read(documentSessionProvider.notifier).dropPng(entry.path);
      ref.read(statusMessageProvider.notifier).state = S.pngDeleted;
    } on StampVaultException catch (error) {
      ref.read(statusMessageProvider.notifier).state = error.message;
    }
  }

  void _onTap(WidgetRef ref) {
    if (entry.isDirectory) {
      ref.read(currentDirectoryProvider.notifier).open(entry.path);
      return;
    }
    if (entry.kind == FileKind.png) {
      ref.read(activeStampPathProvider.notifier).state = entry.path;
      return;
    }
    if (FileBrowserService.isDocument(entry.path)) {
      ref.read(documentSessionProvider.notifier).openPath(entry.path);
    }
  }

  void _onOpen(WidgetRef ref) {
    if (entry.isDirectory) {
      ref.read(currentDirectoryProvider.notifier).open(entry.path);
      return;
    }
    ref.read(documentSessionProvider.notifier).openPath(entry.path);
  }

  IconData _iconFor(FileKind kind) {
    return switch (kind) {
      FileKind.directory => Icons.folder,
      FileKind.png => Icons.image,
      FileKind.pdf => Icons.picture_as_pdf,
      FileKind.docx => Icons.description,
      FileKind.other => Icons.insert_drive_file,
    };
  }
}

class _RenamePngDialog extends StatefulWidget {
  const _RenamePngDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePngDialog> createState() => _RenamePngDialogState();
}

class _RenamePngDialogState extends State<_RenamePngDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(S.renamePngTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: S.renamePngHint,
          suffixText: '.png',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Зберегти'),
        ),
      ],
    );
  }
}

class _StampDragFeedback extends StatelessWidget {
  const _StampDragFeedback({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: Colors.transparent,
      child: SizedBox(
        width: 120,
        height: 80,
        child: StampImage(path: path, fit: BoxFit.contain),
      ),
    );
  }
}
