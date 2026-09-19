import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../strings.dart';
import 'stamp_vault.dart';

class PortableStore {
  static const folderName = 'PNG';
  static const libraryFileName = StampVault.fileName;
  static const deletedFileName = 'pechatky.deleted.json';

  static StampVault? _vault;
  static final _deletedNames = <String>{};
  static bool _deletedLoaded = false;
  static bool _didMigrate = false;

  /// Test-only: clear cached vault/migration state between cases.
  static void debugReset() {
    _vault = null;
    _deletedNames.clear();
    _deletedLoaded = false;
    _didMigrate = false;
  }

  static String storeRoot() {
    if (_isProjectBuild()) {
      final project = _projectRoot();
      if (project != null) {
        return p.join(project.path, 'portable_data');
      }
    }

    final bundled = _bundledRoot();
    if (bundled != null) {
      return bundled;
    }

    final project = _projectRoot();
    if (project != null) {
      return p.join(project.path, 'portable_data');
    }

    return _applicationSupport();
  }

  static String libraryFile() => p.join(storeRoot(), libraryFileName);

  static String deletedListFile() => p.join(storeRoot(), deletedFileName);

  static String stampsDirectory() => p.join(storeRoot(), folderName);

  static String ensureStampsDirectory() {
    Directory(storeRoot()).createSync(recursive: true);
    Directory(stampsDirectory()).createSync(recursive: true);
    _openVault();
    _loadDeletedNames();
    _migrateLegacyPngs();
    return stampsDirectory();
  }

  static bool isStampsDirectory(String path) {
    return p.equals(path, stampsDirectory());
  }

  static bool isLibraryPath(String path) => StampVault.looksLikeVault(path);

  static StampVault _openVault() {
    final path = libraryFile();
    if (_vault == null || _vault!.file.path != path) {
      _vault = StampVault(File(path));
      _deletedLoaded = false;
      _didMigrate = false;
    }
    _vault!.ensure();
    return _vault!;
  }

  static List<FileSystemEntry> listStampEntries() {
    final dir = stampsDirectory();
    return [
      for (final name in _openVault().names)
        if (!_deletedNames.contains(name.toLowerCase()))
          FileSystemEntry(
            path: p.join(dir, name),
            name: name,
            isDirectory: false,
            kind: FileKind.png,
          ),
    ];
  }

  static Uint8List? readPngBytes(String path) {
    if (isLibraryPath(path)) {
      return null;
    }
    final name = p.basename(path);
    if (_isDeleted(name)) {
      return null;
    }
    final vault = _openVault();
    final fromVault = vault.read(name);
    if (fromVault != null) {
      return fromVault;
    }
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsBytesSync();
    }
    return null;
  }

  static Future<List<String>> importPngs(Iterable<String> paths) async {
    final destDir = ensureStampsDirectory();
    final vault = _openVault();
    final imported = <String>[];
    for (final path in paths) {
      if (p.equals(path, libraryFile())) {
        continue;
      }
      if (isLibraryPath(path)) {
        vault.importAllFrom(StampVault(File(path)));
        imported.addAll([
          for (final name in vault.names) p.join(destDir, name),
        ]);
        continue;
      }
      if (p.extension(path).toLowerCase() != '.png') {
        continue;
      }
      final name = p.basename(path);
      final dest = p.join(destDir, name);
      if (vault.contains(name) && p.equals(path, dest)) {
        if (!imported.contains(dest)) {
          imported.add(dest);
        }
        continue;
      }
      vault.put(name, await File(path).readAsBytes());
      _forgetDeleted(name);
      imported.add(dest);
    }
    return imported;
  }

  static String renameStamp(String path, String newName) {
    final next = _openVault().rename(path, newName);
    _forgetDeleted(next);
    return p.join(stampsDirectory(), next);
  }

  static void deleteStamp(String path) {
    final name = p.basename(path);
    _openVault().delete(name);
    _rememberDeleted(name);
    _purgeLooseCopies(name);
  }

  static Future<
    ({List<Map<String, dynamic>> stamps, Future<void> Function() cleanup})
  >
  materializeStamps(List<StampPlacement> stamps) async {
    final tmp = await Directory.systemTemp.createTemp('podpisun_vault_');
    final resolved = <String, String>{};
    final json = <Map<String, dynamic>>[];
    for (final stamp in stamps) {
      var png = resolved[stamp.pngPath];
      if (png == null) {
        final bytes = readPngBytes(stamp.pngPath);
        if (bytes != null) {
          png = p.join(tmp.path, p.basename(stamp.pngPath));
          await File(png).writeAsBytes(bytes, flush: true);
        } else {
          png = stamp.pngPath;
        }
        resolved[stamp.pngPath] = png;
      }
      final map = stamp.toEngineJson();
      map['png'] = png;
      json.add(map);
    }
    return (
      stamps: json,
      cleanup: () async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      },
    );
  }

  static void _loadDeletedNames() {
    if (_deletedLoaded) {
      return;
    }
    _deletedLoaded = true;
    _deletedNames.clear();
    final file = File(deletedListFile());
    if (!file.existsSync()) {
      return;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is List) {
        for (final item in decoded) {
          if (item is String && item.isNotEmpty) {
            _deletedNames.add(item.toLowerCase());
          }
        }
      }
    } on Object {
      // Ignore a corrupt tombstone list; vault remains source of truth.
    }
  }

  static void _rememberDeleted(String name) {
    _loadDeletedNames();
    _deletedNames.add(p.basename(name).toLowerCase());
    _persistDeletedNames();
  }

  static void _forgetDeleted(String name) {
    _loadDeletedNames();
    if (_deletedNames.remove(p.basename(name).toLowerCase())) {
      _persistDeletedNames();
    }
  }

  static bool _isDeleted(String name) {
    _loadDeletedNames();
    return _deletedNames.contains(p.basename(name).toLowerCase());
  }

  static void _persistDeletedNames() {
    Directory(storeRoot()).createSync(recursive: true);
    final file = File(deletedListFile());
    final names = _deletedNames.toList()..sort();
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(names), flush: true);
    tmp.renameSync(file.path);
  }

  static void _purgeLooseCopies(String name) {
    final base = p.basename(name);
    for (final folder in _legacyStampFolders()) {
      final loose = File(p.join(folder.path, base));
      if (!loose.existsSync()) {
        continue;
      }
      try {
        loose.deleteSync();
      } on FileSystemException {
        // Another copy may be locked; tombstone still blocks re-import.
      }
    }
  }

  /// PNG library lives next to the executable: inside Підписун.app on macOS,
  /// beside podpisun.exe on Windows. Copying the app copies the vault file.
  static String? _bundledRoot() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final appBundle = _macosAppBundle();
    if (appBundle != null) {
      if (_isSystemInstall(appBundle.parent.path)) {
        return _applicationSupport();
      }
      if (_canStoreIn(exeDir)) {
        return exeDir.path;
      }
      return _applicationSupport();
    }

    if (Platform.isWindows) {
      if (_isSystemInstall(exeDir.path)) {
        return _applicationSupport();
      }
      if (_canStoreIn(exeDir)) {
        return exeDir.path;
      }
    }

    return null;
  }

  static Directory? _macosAppBundle() {
    if (!Platform.isMacOS) {
      return null;
    }
    final exeDir = File(Platform.resolvedExecutable).parent;
    if (p.basename(exeDir.path) != 'MacOS') {
      return null;
    }
    final contents = exeDir.parent;
    if (p.basename(contents.path) != 'Contents') {
      return null;
    }
    final appBundle = contents.parent;
    if (p.extension(appBundle.path) != '.app') {
      return null;
    }
    return appBundle;
  }

  static bool _isProjectBuild() {
    final project = _projectRoot();
    if (project == null) {
      return false;
    }
    final exe = File(Platform.resolvedExecutable).path;
    final buildDir = p.join(project.path, 'build');
    return p.isWithin(buildDir, exe);
  }

  static void _migrateLegacyPngs() {
    if (_didMigrate) {
      return;
    }
    _didMigrate = true;
    final vault = _openVault();
    _loadDeletedNames();
    for (final source in _legacyStampFolders()) {
      if (!source.existsSync()) {
        continue;
      }
      for (final file in source.listSync().whereType<File>()) {
        if (p.extension(file.path).toLowerCase() != '.png') {
          continue;
        }
        final name = p.basename(file.path);
        if (_isDeleted(name)) {
          try {
            file.deleteSync();
          } on FileSystemException {
            // Tombstone already prevents listing/import.
          }
          continue;
        }
        if (vault.contains(name)) {
          // Already in the vault — remove duplicate loose copy outside store.
          if (!p.equals(p.dirname(file.path), stampsDirectory())) {
            try {
              file.deleteSync();
            } on FileSystemException {
              // Keep the vault copy; ignore locked duplicates.
            }
          }
          continue;
        }
        try {
          vault.put(name, file.readAsBytesSync());
          if (!p.equals(p.dirname(file.path), stampsDirectory())) {
            file.deleteSync();
          }
        } on StampVaultException {
          continue;
        } on FileSystemException {
          continue;
        }
      }
    }
  }

  static Iterable<Directory> _legacyStampFolders() sync* {
    yield Directory(stampsDirectory());
    final appBundle = _macosAppBundle();
    if (appBundle != null) {
      yield Directory(p.join(appBundle.parent.path, folderName));
    }
    final project = _projectRoot();
    if (project != null) {
      yield Directory(p.join(project.path, 'portable_data', folderName));
      yield Directory(
        p.join(
          project.path,
          'build',
          'macos',
          'Build',
          'Products',
          'Debug',
          folderName,
        ),
      );
      yield Directory(
        p.join(
          project.path,
          'build',
          'macos',
          'Build',
          'Products',
          'Release',
          folderName,
        ),
      );
    }
  }

  static Directory? _projectRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        try {
          final text = pubspec.readAsStringSync();
          if (text.contains('name: podpisun')) {
            return dir;
          }
        } on FileSystemException {
          return dir;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    return null;
  }

  static bool _isSystemInstall(String folderPath) {
    final normalized = folderPath.replaceAll('\\', '/');
    return normalized == '/Applications' ||
        normalized.endsWith('/Applications') ||
        normalized.contains('/System/') ||
        normalized.contains('Program Files');
  }

  static bool _canStoreIn(Directory dir) {
    try {
      if (!dir.existsSync()) {
        return false;
      }
      return _isWritable(dir);
    } on FileSystemException {
      return false;
    }
  }

  static bool _isWritable(Directory dir) {
    try {
      if (!dir.existsSync()) {
        return false;
      }
      final probe = File(
        p.join(dir.path, '.podpisun_write_probe_${pidForProbe()}'),
      );
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static int pidForProbe() => pid;

  static String _applicationSupport() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '.';
      return p.join(home, 'Library', 'Application Support', S.appTitle);
    }
    if (Platform.isWindows) {
      final roaming =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      return p.join(roaming, S.appTitle);
    }
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.local', 'share', S.appTitle);
  }
}
