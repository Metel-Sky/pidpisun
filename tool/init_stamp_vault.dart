import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podpisun/services/stamp_vault.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/init_stamp_vault.dart <pechatky.podpisun> [--import-dir DIR]...',
    );
    exit(1);
  }
  final vault = StampVault(File(args[0]), capacity: StampVault.defaultCapacity);
  vault.ensure();
  for (var i = 1; i < args.length; i++) {
    if (args[i] != '--import-dir' || i + 1 >= args.length) {
      continue;
    }
    final dir = Directory(args[++i]);
    if (!dir.existsSync()) {
      continue;
    }
    for (final file in dir.listSync().whereType<File>()) {
      if (p.extension(file.path).toLowerCase() != '.png') {
        continue;
      }
      vault.put(p.basename(file.path), file.readAsBytesSync());
    }
  }
  stdout.writeln(
    '${vault.file.path}  ${vault.file.lengthSync()} bytes  files=${vault.names.length}',
  );
}
