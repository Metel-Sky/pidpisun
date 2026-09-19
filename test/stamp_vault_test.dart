import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:podpisun/services/stamp_vault.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('podpisun_vault');
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('створює файл фіксованого розміру, пише і читає PNG', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    const capacity = 512 * 1024;
    final vault = StampVault(file, capacity: capacity);
    vault.ensure();
    expect(file.lengthSync(), capacity);

    vault.put('seal.png', Uint8List.fromList([1, 2, 3, 4]));
    expect(vault.names, ['seal.png']);
    expect(vault.read('seal.png'), [1, 2, 3, 4]);

    final reopened = StampVault(file, capacity: capacity);
    expect(reopened.read('seal.png'), [1, 2, 3, 4]);
  });

  test('перейменовує і видаляє PNG, місце звільняється', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    final vault = StampVault(
      file,
      capacity: StampVault.payloadStart + 40,
    );
    vault.put('old.png', Uint8List.fromList(List.filled(20, 1)));
    expect(vault.rename('old.png', 'новий'), 'новий.png');
    expect(vault.names, ['новий.png']);
    expect(vault.read('новий.png'), List.filled(20, 1));
    expect(vault.read('old.png'), isNull);

    vault.delete('новий.png');
    expect(vault.names, isEmpty);
    vault.put('b.png', Uint8List.fromList(List.filled(24, 2)));
    expect(vault.read('b.png'), List.filled(24, 2));
  });

  test('видалення і перейменування лишаються після повторного відкриття', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    const capacity = 512 * 1024;
    final vault = StampVault(file, capacity: capacity);
    vault.put('keep.png', Uint8List.fromList([1, 1, 1]));
    vault.put('gone.png', Uint8List.fromList([2, 2, 2]));
    vault.rename('keep.png', 'печатка');
    vault.delete('gone.png');

    final reopened = StampVault(file, capacity: capacity);
    expect(reopened.names, ['печатка.png']);
    expect(reopened.read('печатка.png'), [1, 1, 1]);
    expect(reopened.read('gone.png'), isNull);
  });

  test('не дає перейменувати на зайняте ім’я', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    final vault = StampVault(file, capacity: 512 * 1024);
    vault.put('a.png', Uint8List.fromList([1]));
    vault.put('b.png', Uint8List.fromList([2]));
    expect(
      () => vault.rename('a.png', 'b.png'),
      throwsA(isA<StampVaultException>()),
    );
  });

  test('замінює файл з тим самим іменем', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    final vault = StampVault(file, capacity: 512 * 1024);
    vault.put('seal.png', Uint8List.fromList([1, 2, 3]));
    vault.put('seal.png', Uint8List.fromList([9, 8]));
    expect(vault.read('seal.png'), [9, 8]);
  });

  test('розширює маленький файл печаток, печатки лишаються', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    final small = StampVault(file, capacity: 512 * 1024);
    small.put('a.png', Uint8List.fromList(List.filled(200 * 1024, 1)));
    expect(
      () => small.put('b.png', Uint8List.fromList(List.filled(100 * 1024, 2))),
      throwsA(isA<StampVaultFullException>()),
    );

    final grown = StampVault(file, capacity: 1024 * 1024);
    grown.ensure();
    expect(file.lengthSync(), 1024 * 1024);
    expect(grown.read('a.png'), List.filled(200 * 1024, 1));
    grown.put('b.png', Uint8List.fromList(List.filled(100 * 1024, 2)));
    expect(grown.read('b.png'), List.filled(100 * 1024, 2));
  });

  test('кидає, коли 250 МБ закінчились', () {
    final file = File(p.join(tmp.path, 'pechatky.podpisun'));
    final vault = StampVault(
      file,
      capacity: StampVault.payloadStart + 16,
    );
    vault.put('a.png', Uint8List.fromList([1, 2, 3, 4]));
    expect(
      () => vault.put('b.png', Uint8List.fromList(List.filled(32, 7))),
      throwsA(isA<StampVaultFullException>()),
    );
  });
}
