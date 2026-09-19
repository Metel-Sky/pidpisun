import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';

class FileBrowserService {
  static const allowedExtensions = {'.png', '.pdf', '.docx'};

  static String homeDirectory() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return home;
    }
    return Directory.current.path;
  }

  static FileKind kindFor(String path, {required bool isDirectory}) {
    if (isDirectory) {
      return FileKind.directory;
    }
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return FileKind.png;
      case '.pdf':
        return FileKind.pdf;
      case '.docx':
        return FileKind.docx;
      default:
        return FileKind.other;
    }
  }

  static bool isPng(String path) => p.extension(path).toLowerCase() == '.png';

  static bool isDocument(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.pdf' || ext == '.docx';
  }

  Future<List<FileSystemEntry>> listDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemException('Папку не знайдено', dirPath);
    }

    final entries = <FileSystemEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) {
        continue;
      }
      final isDirectory = entity is Directory;
      if (!isDirectory && entity is! File) {
        continue;
      }
      final kind = kindFor(entity.path, isDirectory: isDirectory);
      if (!isDirectory && kind == FileKind.other) {
        continue;
      }
      entries.add(
        FileSystemEntry(
          path: entity.path,
          name: name,
          isDirectory: isDirectory,
          kind: kind,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}
