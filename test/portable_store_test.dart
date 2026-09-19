import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:podpisun/providers/workspace_providers.dart';
import 'package:podpisun/services/portable_store.dart';
import 'package:podpisun/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('сховище печаток — файл у portable_data', () {
    final dir = PortableStore.ensureStampsDirectory();
    expect(Directory(dir).existsSync(), isTrue);
    expect(p.basename(dir), 'PNG');
    expect(dir.contains('portable_data'), isTrue);
    expect(File(PortableStore.libraryFile()).existsSync(), isTrue);
  });

  test('копіює PNG у файл печаток', () async {
    final tmp = await Directory.systemTemp.createTemp('podpisun_png');
    addTearDown(() => tmp.delete(recursive: true));
    final src = File(p.join(tmp.path, 'seal.png'));
    await src.writeAsBytes(const [1, 2, 3]);

    final imported = await PortableStore.importPngs([src.path]);
    expect(imported, isNotEmpty);
    expect(p.basename(imported.last), 'seal.png');
    expect(PortableStore.readPngBytes(imported.last), [1, 2, 3]);
  });

  test('перейменовує і видаляє PNG у сховищі', () async {
    PortableStore.debugReset();
    final tmp = await Directory.systemTemp.createTemp('podpisun_png');
    addTearDown(() => tmp.delete(recursive: true));
    final src = File(p.join(tmp.path, 'seal.png'));
    await src.writeAsBytes(const [4, 5, 6]);
    final imported = await PortableStore.importPngs([src.path]);
    final renamed = PortableStore.renameStamp(imported.last, 'підпис');
    expect(p.basename(renamed), 'підпис.png');
    expect(PortableStore.readPngBytes(renamed), [4, 5, 6]);
    PortableStore.deleteStamp(renamed);
    expect(PortableStore.readPngBytes(renamed), isNull);
    expect(
      PortableStore.listStampEntries().any((e) => e.name == 'підпис.png'),
      isFalse,
    );

    // Leftover loose copy + "restart" must not bring the stamp back.
    final loose = File(p.join(PortableStore.stampsDirectory(), 'підпис.png'));
    await loose.writeAsBytes(const [7, 8, 9]);
    PortableStore.debugReset();
    PortableStore.ensureStampsDirectory();
    expect(PortableStore.readPngBytes(renamed), isNull);
    expect(
      PortableStore.listStampEntries().any((e) => e.name == 'підпис.png'),
      isFalse,
    );
    expect(loose.existsSync(), isFalse);
  });

  test('стартова тека і закріплені — це PNG', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      p.basename(container.read(currentDirectoryProvider)),
      PortableStore.folderName,
    );
    final folders = await container.read(pinnedFoldersProvider.future);
    expect(folders, isNotEmpty);
    expect(folders.first.name, S.portablePng);
    expect(PortableStore.isStampsDirectory(folders.first.path), isTrue);
  });
}
