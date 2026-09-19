import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/workspace_providers.dart';
import '../services/portable_store.dart';
import '../services/stamp_vault.dart';
import '../strings.dart';

Future<void> importPngsFromDrop(WidgetRef ref, Iterable<String> paths) async {
  try {
    final imported = await PortableStore.importPngs(paths);
    if (imported.isEmpty) {
      return;
    }
    final destDir = PortableStore.ensureStampsDirectory();
    ref.read(currentDirectoryProvider.notifier).open(destDir);
    ref.read(stampLibraryEpochProvider.notifier).state++;
    ref.read(activeStampPathProvider.notifier).state = imported.last;
    ref.read(statusMessageProvider.notifier).state = S.pngImported;
  } on StampVaultException catch (error) {
    ref.read(statusMessageProvider.notifier).state = error.message;
  }
}
