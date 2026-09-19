import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PythonEngineException implements Exception {
  PythonEngineException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _EngineLaunch {
  const _EngineLaunch({required this.executable, this.prefixArgs = const []});

  final String executable;
  final List<String> prefixArgs;
}

class PythonEngine {
  PythonEngine({Directory? startFrom}) : _startFrom = startFrom;

  final Directory? _startFrom;
  _EngineLaunch? _cached;

  Future<void> convertDocx({
    required String inputPath,
    required String outputPath,
  }) {
    return _run(['convert', '--in', inputPath, '--out', outputPath]);
  }

  Future<void> stampPdf({
    required String inputPath,
    required String outputPath,
    required List<Map<String, dynamic>> stamps,
  }) async {
    final stampsFile = File(
      p.join(
        Directory.systemTemp.path,
        'podpisun_stamps_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    await stampsFile.writeAsString(jsonEncode(stamps), encoding: utf8);
    try {
      await _run([
        'stamp',
        '--in',
        inputPath,
        '--out',
        outputPath,
        '--stamps',
        stampsFile.path,
      ]);
    } finally {
      if (await stampsFile.exists()) {
        await stampsFile.delete();
      }
    }
  }

  Future<bool> isAvailable() async {
    try {
      await _resolve();
      return true;
    } on PythonEngineException {
      return false;
    }
  }

  Future<_EngineLaunch> _resolve() async {
    if (_cached != null) {
      return _cached!;
    }

    final bundled = await _findBundledEngine();
    if (bundled != null) {
      _cached = bundled;
      return bundled;
    }

    final root = await _findProjectRoot();
    if (root == null) {
      throw PythonEngineException(
        'Не знайдено Python-рушій. Перевстановіть Підписун або виконайте:\n'
        'python3 -m venv engine/.venv && '
        'engine/.venv/bin/pip install -r engine/requirements.txt',
      );
    }
    final script = File(p.join(root.path, 'engine', 'main.py'));
    if (!await script.exists()) {
      throw PythonEngineException('Не знайдено engine/main.py.');
    }

    final venvCandidates = [
      File(p.join(root.path, 'engine', '.venv', 'bin', 'python3')),
      File(p.join(root.path, 'engine', '.venv', 'bin', 'python')),
      File(p.join(root.path, 'engine', '.venv', 'Scripts', 'python.exe')),
    ];
    for (final python in venvCandidates) {
      if (await python.exists()) {
        _cached = _EngineLaunch(
          executable: python.path,
          prefixArgs: [script.path],
        );
        return _cached!;
      }
    }

    for (final command in ['python3', 'python']) {
      if (await _commandExists(command)) {
        _cached = _EngineLaunch(executable: command, prefixArgs: [script.path]);
        return _cached!;
      }
    }

    throw PythonEngineException(
      'Не знайдено Python-рушій. У теці проєкту виконайте:\n'
      'python3 -m venv engine/.venv && '
      'engine/.venv/bin/pip install -r engine/requirements.txt',
    );
  }

  Future<_EngineLaunch?> _findBundledEngine() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <File>[
      File(p.join(exeDir.path, 'podpisun_engine', 'podpisun_engine')),
      File(p.join(exeDir.path, 'podpisun_engine', 'podpisun_engine.exe')),
      File(p.join(exeDir.path, 'podpisun_engine')),
      File(p.join(exeDir.path, 'podpisun_engine.exe')),
      File(
        p.join(
          exeDir.parent.path,
          'Resources',
          'podpisun_engine',
          'podpisun_engine',
        ),
      ),
    ];
    for (final file in candidates) {
      if (await file.exists()) {
        return _EngineLaunch(executable: file.path);
      }
    }
    return null;
  }

  Future<void> _run(List<String> args) async {
    final launch = await _resolve();
    final result = await Process.run(
      launch.executable,
      [...launch.prefixArgs, ...args],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    Map<String, dynamic>? payload;
    final stdout = result.stdout.toString().trim();
    if (stdout.isNotEmpty) {
      for (final line in stdout.split('\n').reversed) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
            break;
          }
        } on FormatException {
          continue;
        }
      }
    }

    if (result.exitCode == 0 && payload?['ok'] == true) {
      return;
    }

    final stderr = result.stderr.toString().trim();
    final error =
        payload?['error'] as String? ?? (stderr.isNotEmpty ? stderr : stdout);
    throw PythonEngineException(
      error.isEmpty
          ? 'Python-рушій завершився з кодом ${result.exitCode}'
          : error,
    );
  }

  Future<Directory?> _findProjectRoot() async {
    final seeds = <Directory>[
      if (_startFrom != null) _startFrom,
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final seed in seeds) {
      var dir = seed;
      for (var i = 0; i < 16; i++) {
        final script = File(p.join(dir.path, 'engine', 'main.py'));
        final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
        if (await script.exists() && await pubspec.exists()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) {
          break;
        }
        dir = parent;
      }
    }
    return null;
  }

  Future<bool> _commandExists(String command) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        command,
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
