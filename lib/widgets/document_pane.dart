import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../providers/workspace_providers.dart';
import '../models/models.dart';
import '../services/file_browser_service.dart';
import '../strings.dart';
import 'stamp_overlay.dart';

class DocumentPane extends ConsumerStatefulWidget {
  const DocumentPane({super.key});

  @override
  ConsumerState<DocumentPane> createState() => _DocumentPaneState();
}

class _DocumentPaneState extends ConsumerState<DocumentPane> {
  final PdfViewerController _controller = PdfViewerController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _openDroppedPaths(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    final documents = paths.where(FileBrowserService.isDocument).toList();
    final pngs = paths.where(FileBrowserService.isPng).toList();
    if (documents.isNotEmpty) {
      await ref
          .read(documentSessionProvider.notifier)
          .openPath(documents.first);
      return;
    }
    if (pngs.isEmpty) {
      return;
    }
    final session = ref.read(documentSessionProvider);
    if (session == null) {
      ref.read(activeStampPathProvider.notifier).state = pngs.first;
      return;
    }
    var pageWidth = 595.0;
    var pageHeight = 842.0;
    final pageIndex = ref.read(currentPageIndexProvider);
    if (_controller.isReady && _controller.pages.isNotEmpty) {
      final index = pageIndex.clamp(0, _controller.pages.length - 1).toInt();
      final page = _controller.pages[index];
      pageWidth = page.width;
      pageHeight = page.height;
    }
    await ref
        .read(documentSessionProvider.notifier)
        .addStamp(
          pngPath: pngs.first,
          pageIndex: pageIndex,
          x: 72,
          y: 72,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
        );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final selected = ref.read(documentSessionProvider)?.selectedStampId;
    if (selected == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      ref.read(documentSessionProvider.notifier).removeSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildBody(DocumentSession? session, ThemeData theme) {
    if (session == null || !File(session.pdfPath).existsSync()) {
      if (session?.busyMessage != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(session!.busyMessage!),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(S.dropDocument, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(S.dropDocumentHint, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Stack(
      children: [
        PdfViewer.file(
          session.pdfPath,
          key: ValueKey(session.pdfPath),
          controller: _controller,
          params: PdfViewerParams(
            panEnabled: true,
            scaleEnabled: true,
            errorBannerBuilder: (context, error, stackTrace, documentRef) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Не вдалося відкрити PDF.\n$error',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
            pageOverlaysBuilder: (context, pageRect, page) {
              if (page.width <= 0 || page.height <= 0) {
                return const [];
              }
              return [StampPageOverlay(page: page)];
            },
            onViewerReady: (document, controller) {
              if (mounted) {
                setState(() {});
              }
            },
            onPageChanged: (pageNumber) {
              if (pageNumber != null) {
                ref.read(currentPageIndexProvider.notifier).state =
                    pageNumber - 1;
              }
            },
          ),
        ),
        if (session.busyMessage != null)
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(session.busyMessage!),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(documentSessionProvider);
    final theme = Theme.of(context);

    return DropTarget(
      onDragDone: (details) {
        _openDroppedPaths(details.files.map((file) => file.path).toList());
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            _DocumentToolbar(controller: _controller),
            Expanded(child: _buildBody(session, theme)),
          ],
        ),
      ),
    );
  }
}

class _DocumentToolbar extends ConsumerWidget {
  const _DocumentToolbar({required this.controller});

  final PdfViewerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(documentSessionProvider);
    final pageIndex = ref.watch(currentPageIndexProvider);
    StampPlacement? selectedStamp;
    if (session?.selectedStampId != null) {
      for (final stamp in session!.stamps) {
        if (stamp.id == session.selectedStampId) {
          selectedStamp = stamp;
          break;
        }
      }
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var pageCount = 0;
        var pageWidth = 595.0;
        var pageHeight = 842.0;
        try {
          if (controller.isReady) {
            pageCount = controller.pageCount;
            final pages = controller.pages;
            if (pages.isNotEmpty) {
              final index = (selectedStamp?.pageIndex ?? pageIndex)
                  .clamp(0, pages.length - 1)
                  .toInt();
              pageWidth = pages[index].width;
              pageHeight = pages[index].height;
            }
          }
        } catch (_) {
          pageCount = 0;
        }

        return Material(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session == null
                        ? 'Документ'
                        : p.basename(session.originalPath),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (selectedStamp != null) ...[
                  _StampMmSize(
                    stamp: selectedStamp,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  tooltip: S.previousPage,
                  onPressed: session == null || pageIndex <= 0
                      ? null
                      : () => controller.goToPage(pageNumber: pageIndex),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  pageCount == 0
                      ? '—'
                      : '${S.page} ${pageIndex + 1} / $pageCount',
                ),
                IconButton(
                  tooltip: S.nextPage,
                  onPressed:
                      session == null ||
                          pageCount == 0 ||
                          pageIndex + 1 >= pageCount
                      ? null
                      : () => controller.goToPage(pageNumber: pageIndex + 2),
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StampMmSize extends ConsumerStatefulWidget {
  const _StampMmSize({
    required this.stamp,
    required this.pageWidth,
    required this.pageHeight,
  });

  final StampPlacement stamp;
  final double pageWidth;
  final double pageHeight;

  @override
  ConsumerState<_StampMmSize> createState() => _StampMmSizeState();
}

class _StampMmSizeState extends ConsumerState<_StampMmSize> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late String _stampId;
  late double _lastWidth;
  late double _lastHeight;

  @override
  void initState() {
    super.initState();
    _stampId = widget.stamp.id;
    _lastWidth = widget.stamp.width;
    _lastHeight = widget.stamp.height;
    _width = TextEditingController(
      text: StampPlacement.formatMm(
        StampPlacement.pointsToMm(widget.stamp.width),
      ),
    );
    _height = TextEditingController(
      text: StampPlacement.formatMm(
        StampPlacement.pointsToMm(widget.stamp.height),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _StampMmSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stamp = widget.stamp;
    if (stamp.id != _stampId ||
        stamp.width != _lastWidth ||
        stamp.height != _lastHeight) {
      _stampId = stamp.id;
      _lastWidth = stamp.width;
      _lastHeight = stamp.height;
      _width.text = StampPlacement.formatMm(
        StampPlacement.pointsToMm(stamp.width),
      );
      _height.text = StampPlacement.formatMm(
        StampPlacement.pointsToMm(stamp.height),
      );
    }
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _apply({required bool fromWidth}) {
    final widthMm = StampPlacement.parseMm(_width.text);
    final heightMm = StampPlacement.parseMm(_height.text);
    ref.read(documentSessionProvider.notifier).setSelectedSizeMm(
          widthMm: fromWidth ? widthMm : null,
          heightMm: fromWidth ? null : heightMm,
          pageWidth: widget.pageWidth,
          pageHeight: widget.pageHeight,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(S.stampSize, style: theme.textTheme.labelMedium),
        const SizedBox(width: 8),
        _mmField(
          controller: _width,
          tooltip: S.stampWidthMm,
          onSubmit: () => _apply(fromWidth: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('×', style: theme.textTheme.labelMedium),
        ),
        _mmField(
          controller: _height,
          tooltip: S.stampHeightMm,
          onSubmit: () => _apply(fromWidth: false),
        ),
        const SizedBox(width: 4),
        Text(S.mm, style: theme.textTheme.labelMedium),
      ],
    );
  }

  Widget _mmField({
    required TextEditingController controller,
    required String tooltip,
    required VoidCallback onSubmit,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 64,
        child: TextField(
          controller: controller,
          textAlign: TextAlign.end,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: Theme.of(context).textTheme.bodySmall,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => onSubmit(),
          onEditingComplete: onSubmit,
          onTapOutside: (_) => onSubmit(),
        ),
      ),
    );
  }
}
