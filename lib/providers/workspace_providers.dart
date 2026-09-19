import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../services/file_browser_service.dart';
import '../services/pinned_folders_store.dart';
import '../services/portable_store.dart';
import '../services/python_engine.dart';
import '../services/stamp_vault.dart';
import '../strings.dart';

final fileBrowserServiceProvider = Provider<FileBrowserService>((ref) {
  return FileBrowserService();
});

final pythonEngineProvider = Provider<PythonEngine>((ref) {
  return PythonEngine();
});

final pinnedFoldersStoreProvider = Provider<PinnedFoldersStore>((ref) {
  return PinnedFoldersStore();
});

final pythonEngineAvailableProvider = FutureProvider<bool>((ref) {
  return ref.watch(pythonEngineProvider).isAvailable();
});

final currentDirectoryProvider =
    NotifierProvider<CurrentDirectoryNotifier, String>(
      CurrentDirectoryNotifier.new,
    );

class CurrentDirectoryNotifier extends Notifier<String> {
  @override
  String build() => PortableStore.ensureStampsDirectory();

  void open(String path) {
    state = path;
  }

  void goUp() {
    if (PortableStore.isStampsDirectory(state)) {
      return;
    }
    final parent = Directory(state).parent.path;
    if (parent != state) {
      state = parent;
    }
  }
}

final stampLibraryEpochProvider = StateProvider<int>((ref) => 0);

final directoryListingProvider = FutureProvider<List<FileSystemEntry>>((
  ref,
) async {
  ref.watch(stampLibraryEpochProvider);
  final dir = ref.watch(currentDirectoryProvider);
  if (PortableStore.isStampsDirectory(dir)) {
    return PortableStore.listStampEntries();
  }
  return ref.watch(fileBrowserServiceProvider).listDirectory(dir);
});

final pinnedFoldersProvider =
    AsyncNotifierProvider<PinnedFoldersNotifier, List<PinnedFolder>>(
      PinnedFoldersNotifier.new,
    );

class PinnedFoldersNotifier extends AsyncNotifier<List<PinnedFolder>> {
  @override
  Future<List<PinnedFolder>> build() async {
    final stored = await ref.read(pinnedFoldersStoreProvider).load();
    return _withPortable(stored);
  }

  Future<void> pin(String path) async {
    final current = await future;
    if (current.any((folder) => p.equals(folder.path, path))) {
      return;
    }
    final updated = _withPortable([
      ...current,
      PinnedFolder(name: p.basename(path), path: path),
    ]);
    state = AsyncData(updated);
    await ref.read(pinnedFoldersStoreProvider).save(_withoutPortable(updated));
  }

  Future<void> unpin(String path) async {
    if (PortableStore.isStampsDirectory(path)) {
      return;
    }
    final current = await future;
    final updated = _withPortable(
      current.where((folder) => !p.equals(folder.path, path)).toList(),
    );
    state = AsyncData(updated);
    await ref.read(pinnedFoldersStoreProvider).save(_withoutPortable(updated));
  }

  List<PinnedFolder> _withPortable(List<PinnedFolder> folders) {
    final portable = PortableStore.ensureStampsDirectory();
    final rest = folders
        .where((folder) => !p.equals(folder.path, portable))
        .toList();
    return [PinnedFolder(name: S.portablePng, path: portable), ...rest];
  }

  List<PinnedFolder> _withoutPortable(List<PinnedFolder> folders) {
    return folders
        .where((folder) => !PortableStore.isStampsDirectory(folder.path))
        .toList();
  }
}

final activeStampPathProvider = StateProvider<String?>((ref) => null);
final draggingStampPathProvider = StateProvider<String?>((ref) => null);
final currentPageIndexProvider = StateProvider<int>((ref) => 0);
final statusMessageProvider = StateProvider<String?>((ref) => null);
final defaultStampOpacityProvider = StateProvider<double>((ref) => 1);
final defaultStampColorProvider = StateProvider<int?>((ref) => null);

final documentSessionProvider =
    NotifierProvider<DocumentSessionNotifier, DocumentSession?>(
      DocumentSessionNotifier.new,
    );

class DocumentSessionNotifier extends Notifier<DocumentSession?> {
  @override
  DocumentSession? build() => null;

  Future<void> openPath(String path) async {
    final kind = FileBrowserService.kindFor(path, isDirectory: false);
    if (kind == FileKind.png) {
      ref.read(activeStampPathProvider.notifier).state = path;
      return;
    }
    if (PortableStore.isLibraryPath(path)) {
      try {
        final imported = await PortableStore.importPngs([path]);
        ref.read(activeStampPathProvider.notifier).state = imported.isEmpty
            ? path
            : imported.last;
        ref.read(stampLibraryEpochProvider.notifier).state++;
      } on StampVaultException catch (error) {
        ref.read(statusMessageProvider.notifier).state = error.message;
      }
      return;
    }
    if (kind == FileKind.pdf) {
      ref.read(currentPageIndexProvider.notifier).state = 0;
      state = DocumentSession(
        originalPath: path,
        pdfPath: path,
        convertedFromDocx: false,
      );
      return;
    }
    if (kind != FileKind.docx) {
      ref.read(statusMessageProvider.notifier).state =
          'Підтримуються лише PNG, PDF і DOCX.';
      return;
    }

    final engine = ref.read(pythonEngineProvider);
    final output = p.join(
      Directory.systemTemp.path,
      'podpisun_${p.basenameWithoutExtension(path)}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    state = DocumentSession(
      originalPath: path,
      pdfPath: output,
      convertedFromDocx: true,
      busyMessage: S.converting,
    );
    try {
      await engine.convertDocx(inputPath: path, outputPath: output);
      ref.read(currentPageIndexProvider.notifier).state = 0;
      state = DocumentSession(
        originalPath: path,
        pdfPath: output,
        convertedFromDocx: true,
      );
    } on PythonEngineException catch (error) {
      state = null;
      ref.read(statusMessageProvider.notifier).state = error.message;
    } catch (error) {
      state = null;
      ref.read(statusMessageProvider.notifier).state = error.toString();
    }
  }

  void selectStamp(String? id) {
    final session = state;
    if (session == null) {
      return;
    }
    state = session.copyWith(selectedStampId: id, clearSelection: id == null);
  }

  Future<void> addStamp({
    required String pngPath,
    required int pageIndex,
    required double x,
    required double y,
    required double pageWidth,
    required double pageHeight,
  }) async {
    final session = state;
    if (session == null) {
      return;
    }
    final size = await _stampSize(pngPath);
    final width = size.width.clamp(24, pageWidth);
    final height = (width / size.aspectRatio).clamp(24, pageHeight);
    final clampedX = x.clamp(0, (pageWidth - width).clamp(0, pageWidth));
    final clampedY = y.clamp(0, (pageHeight - height).clamp(0, pageHeight));
    final stamp = StampPlacement(
      id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
      pageIndex: pageIndex,
      x: clampedX.toDouble(),
      y: clampedY.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
      pngPath: pngPath,
      aspectRatio: size.aspectRatio,
      opacity: ref.read(defaultStampOpacityProvider),
      color: ref.read(defaultStampColorProvider),
    );
    state = session.copyWith(
      stamps: [...session.stamps, stamp],
      selectedStampId: stamp.id,
    );
    ref.read(activeStampPathProvider.notifier).state = pngPath;
  }

  void setSelectedOpacity(double opacity) {
    final session = state;
    final selectedId = session?.selectedStampId;
    if (session == null || selectedId == null) {
      return;
    }
    state = session.copyWith(
      stamps: [
        for (final stamp in session.stamps)
          if (stamp.id == selectedId)
            stamp.copyWith(opacity: opacity.clamp(0.15, 1.0))
          else
            stamp,
      ],
      selectedStampId: selectedId,
    );
  }

  void setSelectedColor(int? color) {
    final session = state;
    final selectedId = session?.selectedStampId;
    if (session == null || selectedId == null) {
      return;
    }
    state = session.copyWith(
      stamps: [
        for (final stamp in session.stamps)
          if (stamp.id == selectedId)
            stamp.copyWith(color: color, clearColor: color == null)
          else
            stamp,
      ],
      selectedStampId: selectedId,
    );
  }

  void setSelectedSizeMm({
    double? widthMm,
    double? heightMm,
    required double pageWidth,
    required double pageHeight,
  }) {
    final session = state;
    final selectedId = session?.selectedStampId;
    if (session == null || selectedId == null) {
      return;
    }
    if ((widthMm == null || widthMm <= 0) &&
        (heightMm == null || heightMm <= 0)) {
      return;
    }
    state = session.copyWith(
      stamps: [
        for (final stamp in session.stamps)
          if (stamp.id == selectedId)
            _scaledStamp(
              stamp,
              widthMm: widthMm,
              heightMm: heightMm,
              pageWidth: pageWidth,
              pageHeight: pageHeight,
            )
          else
            stamp,
      ],
      selectedStampId: selectedId,
    );
  }

  StampPlacement _scaledStamp(
    StampPlacement stamp, {
    double? widthMm,
    double? heightMm,
    required double pageWidth,
    required double pageHeight,
  }) {
    final aspect = stamp.aspectRatio > 0
        ? stamp.aspectRatio
        : (stamp.height <= 0 ? 1.0 : stamp.width / stamp.height);
    late final double width;
    late final double height;
    if (widthMm != null && widthMm > 0) {
      width = StampPlacement.mmToPoints(widthMm);
      height = width / aspect;
    } else {
      height = StampPlacement.mmToPoints(heightMm!);
      width = height * aspect;
    }
    const minSize = StampPlacement.minSizePoints;
    var w = width;
    var h = height;
    if (w < minSize) {
      w = minSize;
      h = w / aspect;
    }
    if (h < minSize) {
      h = minSize;
      w = h * aspect;
    }
    if (w > pageWidth) {
      w = pageWidth;
      h = w / aspect;
    }
    if (h > pageHeight) {
      h = pageHeight;
      w = h * aspect;
    }
    if (w > pageWidth) {
      w = pageWidth;
      h = w / aspect;
    }
    final x = (stamp.x).clamp(0, (pageWidth - w).clamp(0, pageWidth));
    final y = (stamp.y).clamp(0, (pageHeight - h).clamp(0, pageHeight));
    return stamp.copyWith(
      x: x.toDouble(),
      y: y.toDouble(),
      width: w,
      height: h,
    );
  }

  void setSelectedRotation(double degrees) {
    final session = state;
    final selectedId = session?.selectedStampId;
    if (session == null || selectedId == null) {
      return;
    }
    final rotation = StampPlacement.normalizeRotation(degrees);
    state = session.copyWith(
      stamps: [
        for (final stamp in session.stamps)
          if (stamp.id == selectedId)
            stamp.copyWith(rotation: rotation)
          else
            stamp,
      ],
      selectedStampId: selectedId,
    );
  }

  void updateStamp(StampPlacement updated) {
    final session = state;
    if (session == null) {
      return;
    }
    state = session.copyWith(
      stamps: [
        for (final stamp in session.stamps)
          if (stamp.id == updated.id) updated else stamp,
      ],
      selectedStampId: updated.id,
    );
  }

  void removeSelected() {
    final session = state;
    final selected = session?.selectedStampId;
    if (session == null || selected == null) {
      return;
    }
    state = session.copyWith(
      stamps: session.stamps.where((stamp) => stamp.id != selected).toList(),
      clearSelection: true,
    );
  }

  void removeStamp(String id) {
    final session = state;
    if (session == null) {
      return;
    }
    state = session.copyWith(
      stamps: session.stamps.where((stamp) => stamp.id != id).toList(),
      clearSelection: session.selectedStampId == id,
    );
  }

  void retargetPng(String from, String to) {
    final session = state;
    if (session == null) {
      return;
    }
    state = session.copyWith(
      stamps: [
        for (final stamp in session.stamps)
          p.equals(stamp.pngPath, from) ? stamp.copyWith(pngPath: to) : stamp,
      ],
    );
  }

  void dropPng(String path) {
    final session = state;
    if (session == null) {
      return;
    }
    final selected = session.stamps
        .where((stamp) => stamp.id == session.selectedStampId)
        .firstOrNull;
    final removedSelected =
        selected != null && p.equals(selected.pngPath, path);
    state = session.copyWith(
      stamps: session.stamps
          .where((stamp) => !p.equals(stamp.pngPath, path))
          .toList(),
      clearSelection: removedSelected,
    );
  }

  Future<void> saveAs() async {
    final session = state;
    if (session == null) {
      ref.read(statusMessageProvider.notifier).state = S.noDocument;
      return;
    }

    if (session.stamps.isEmpty) {
      ref.read(statusMessageProvider.notifier).state =
          'Немає печаток на документі — збережіть після накладання PNG.';
      return;
    }

    final suggested =
        '${p.basenameWithoutExtension(session.originalPath)}_підпис.pdf';
    String? output;
    try {
      output = await FilePicker.platform.saveFile(
        dialogTitle: S.savePdf,
        fileName: suggested,
        initialDirectory: p.dirname(session.originalPath),
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        lockParentWindow: true,
      );
    } on PlatformException catch (error) {
      ref.read(statusMessageProvider.notifier).state =
          'Не вдалося відкрити діалог збереження: ${error.message ?? error.code}';
      return;
    }
    if (output == null) {
      ref.read(statusMessageProvider.notifier).state = S.cancelled;
      return;
    }
    final outPath = p.extension(output).toLowerCase() == '.pdf'
        ? output
        : '$output.pdf';

    state = session.copyWith(busyMessage: S.saving);
    final materialized = await PortableStore.materializeStamps(session.stamps);
    try {
      await ref
          .read(pythonEngineProvider)
          .stampPdf(
            inputPath: session.pdfPath,
            outputPath: outPath,
            stamps: materialized.stamps,
          );
      state = session.copyWith(clearBusy: true);
      ref.read(statusMessageProvider.notifier).state = '${S.saved}: $outPath';
    } on PythonEngineException catch (error) {
      state = session.copyWith(clearBusy: true);
      ref.read(statusMessageProvider.notifier).state = error.message;
    } catch (error) {
      state = session.copyWith(clearBusy: true);
      ref.read(statusMessageProvider.notifier).state = error.toString();
    } finally {
      await materialized.cleanup();
    }
  }

  Future<({double width, double aspectRatio})> _stampSize(
    String pngPath,
  ) async {
    const targetWidth = 108.0;
    try {
      final bytes =
          PortableStore.readPngBytes(pngPath) ??
          await File(pngPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width.toDouble();
      final height = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      final aspect = width <= 0 || height <= 0 ? 2.0 : width / height;
      return (width: targetWidth, aspectRatio: aspect);
    } catch (_) {
      return (width: targetWidth, aspectRatio: 2.0);
    }
  }
}
