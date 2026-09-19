import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class StampVaultException implements Exception {
  StampVaultException(this.message);
  final String message;

  @override
  String toString() => message;
}

class StampVaultFullException extends StampVaultException {
  StampVaultFullException()
    : super(
        'У файлі печаток закінчилось місце (250 МБ). '
        'Видаліть зайві PNG або скопіюйте файл на диск із вільним місцем.',
      );
}

class _Entry {
  _Entry({required this.name, required this.offset, required this.length});

  String name;
  int offset;
  int length;
}

/// Fixed-size PNG library: one file you can copy between computers.
class StampVault {
  StampVault(this.file, {int? capacity})
    : capacity = capacity ?? defaultCapacityForNewFiles();

  final File file;
  final int capacity;

  static const fileName = 'pechatky.podpisun';
  static const defaultCapacity = 250 * 1024 * 1024;
  static const payloadStart = 256 * 1024;
  static const _headerSize = 32;
  static const _version = 1;
  static final _magic = Uint8List.fromList([0x50, 0x50, 0x53, 0x4E]); // PPSN
  static const _chunk = 1024 * 1024;

  static int defaultCapacityForNewFiles() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return 1024 * 1024;
    }
    return defaultCapacity;
  }

  static bool looksLikeVault(String path) {
    final name = p.basename(path).toLowerCase();
    if (name == fileName || p.extension(path).toLowerCase() == '.podpisun') {
      return true;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    try {
      final handle = file.openSync();
      try {
        if (handle.lengthSync() < _magic.length) {
          return false;
        }
        final bytes = handle.readSync(_magic.length);
        return _bytesEqual(bytes, _magic);
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  final _cache = <String, Uint8List>{};
  List<_Entry> _entries = [];
  int _payloadUsed = 0;
  int _allocated = 0;
  bool _ready = false;
  File get _sidecar => File('${file.path}.idx');

  int get usedBytes => _payloadUsed;

  int get allocatedBytes => _allocated == 0 ? capacity : _allocated;

  int get freeBytes =>
      (allocatedBytes - payloadStart - _payloadUsed).clamp(0, allocatedBytes);

  List<String> get names {
    _ensureReady();
    final list = [for (final entry in _entries) entry.name];
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void ensure() => _ensureReady();

  bool contains(String name) {
    _ensureReady();
    return _find(p.basename(name)) != null;
  }

  Uint8List? read(String name) {
    _ensureReady();
    final key = p.basename(name);
    final cached = _cache[key.toLowerCase()];
    if (cached != null) {
      return cached;
    }
    final entry = _find(key);
    if (entry == null) {
      return null;
    }
    final handle = file.openSync();
    try {
      handle.setPositionSync(payloadStart + entry.offset);
      final bytes = Uint8List.fromList(handle.readSync(entry.length));
      _cache[key.toLowerCase()] = bytes;
      return bytes;
    } finally {
      handle.closeSync();
    }
  }

  void put(String name, List<int> bytes) {
    _ensureReady();
    final key = p.basename(name);
    if (p.extension(key).toLowerCase() != '.png') {
      throw StampVaultException('У файл печаток можна класти лише PNG.');
    }
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final existing = _find(key);
    if (existing != null && data.length <= existing.length) {
      _writePayload(existing.offset, data);
      existing.length = data.length;
      existing.name = key;
    } else {
      if (data.length > freeBytes) {
        throw StampVaultFullException();
      }
      final offset = _payloadUsed;
      _writePayload(offset, data);
      _payloadUsed += data.length;
      if (existing == null) {
        _entries.add(_Entry(name: key, offset: offset, length: data.length));
      } else {
        existing.offset = offset;
        existing.length = data.length;
        existing.name = key;
      }
    }
    _cache[key.toLowerCase()] = Uint8List.fromList(data);
    _writeIndex();
  }

  void delete(String name) {
    _ensureReady();
    final entry = _find(p.basename(name));
    if (entry == null) {
      return;
    }
    _entries.removeWhere(
      (item) => item.name.toLowerCase() == entry.name.toLowerCase(),
    );
    _cache.remove(entry.name.toLowerCase());
    _compact();
  }

  String rename(String from, String to) {
    _ensureReady();
    final source = _find(p.basename(from));
    if (source == null) {
      throw StampVaultException('PNG не знайдено у файлі печаток.');
    }
    final next = normalizeName(to);
    final clash = _find(next);
    if (clash != null && !identical(clash, source)) {
      throw StampVaultException('Файл «$next» уже є у печатках.');
    }
    final bytes = _cache.remove(source.name.toLowerCase());
    source.name = next;
    if (bytes != null) {
      _cache[next.toLowerCase()] = bytes;
    }
    _writeIndex();
    return next;
  }

  static String normalizeName(String raw) {
    var next = p.basename(raw.trim());
    next = next.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '');
    next = next.trim();
    if (next.toLowerCase().endsWith('.png')) {
      next = next.substring(0, next.length - 4).trim();
    }
    if (next.isEmpty || next == '.' || next == '..') {
      throw StampVaultException('Вкажіть назву файлу.');
    }
    return '$next.png';
  }

  void importAllFrom(StampVault other) {
    other._ensureReady();
    for (final name in other.names) {
      final bytes = other.read(name);
      if (bytes != null) {
        put(name, bytes);
      }
    }
  }

  void _compact() {
    if (_entries.isEmpty) {
      _payloadUsed = 0;
      _writeIndex();
      return;
    }
    final packed = <({_Entry entry, Uint8List bytes})>[];
    for (final entry in List<_Entry>.from(_entries)) {
      final bytes = read(entry.name);
      if (bytes == null) {
        continue;
      }
      packed.add((entry: entry, bytes: bytes));
    }
    var offset = 0;
    for (final item in packed) {
      _writePayload(offset, item.bytes);
      item.entry.offset = offset;
      item.entry.length = item.bytes.length;
      offset += item.bytes.length;
    }
    _payloadUsed = offset;
    _writeIndex();
  }

  bool _hasMagic() {
    try {
      final handle = file.openSync();
      try {
        return _bytesEqual(handle.readSync(_magic.length), _magic);
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _ensureReady() {
    if (_ready && file.existsSync()) {
      _growTo(capacity);
      return;
    }
    Directory(p.dirname(file.path)).createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() >= payloadStart) {
      if (_load()) {
        _ready = true;
        _growTo(capacity);
        return;
      }
      if (_hasMagic()) {
        throw StampVaultException('Файл печаток пошкоджено: ${file.path}');
      }
      _allocated = file.lengthSync();
      _entries = [];
      _payloadUsed = 0;
      _cache.clear();
      _writeIndex();
      _ready = true;
      _growTo(capacity);
      return;
    }
    _create();
    _ready = true;
  }

  void _growTo(int target) {
    if (target <= allocatedBytes && file.lengthSync() >= target) {
      return;
    }
    final handle = file.openSync(mode: FileMode.append);
    try {
      var pos = file.lengthSync();
      handle.setPositionSync(pos);
      final zeros = Uint8List(_chunk);
      while (pos < target) {
        final n = target - pos < _chunk ? target - pos : _chunk;
        if (n == _chunk) {
          handle.writeFromSync(zeros);
        } else {
          handle.writeFromSync(zeros, 0, n);
        }
        pos += n;
      }
    } finally {
      handle.closeSync();
    }
    _allocated = target;
    _writeIndex();
  }

  bool _load() {
    if (_loadSidecar()) {
      return true;
    }
    final handle = file.openSync();
    try {
      final header = handle.readSync(_headerSize);
      if (header.length < _headerSize ||
          !_bytesEqual(header.sublist(0, 4), _magic)) {
        return false;
      }
      final view = ByteData.sublistView(Uint8List.fromList(header));
      final version = view.getUint32(4, Endian.little);
      if (version != _version) {
        return false;
      }
      final storedCapacity = view.getUint64(8, Endian.little);
      final storedPayloadStart = view.getUint32(16, Endian.little);
      if (storedPayloadStart != payloadStart || storedCapacity < payloadStart) {
        return false;
      }
      _payloadUsed = view.getUint64(20, Endian.little);
      _allocated = storedCapacity;
      final indexLength = view.getUint32(28, Endian.little);
      if (indexLength > payloadStart - _headerSize) {
        return false;
      }
      handle.setPositionSync(_headerSize);
      final indexBytes = handle.readSync(indexLength);
      final decoded = jsonDecode(utf8.decode(indexBytes));
      if (decoded is! List) {
        return false;
      }
      _entries = [
        for (final item in decoded)
          if (item is Map)
            _Entry(
              name: item['n'] as String? ?? '',
              offset: (item['o'] as num?)?.toInt() ?? 0,
              length: (item['l'] as num?)?.toInt() ?? 0,
            ),
      ]..removeWhere((entry) => entry.name.isEmpty || entry.length < 0);
      return true;
    } on Object {
      return false;
    } finally {
      handle.closeSync();
    }
  }

  bool _loadSidecar() {
    if (!_sidecar.existsSync()) {
      return false;
    }
    try {
      final decoded = jsonDecode(_sidecar.readAsStringSync());
      if (decoded is! Map) {
        return false;
      }
      final files = decoded['files'];
      if (files is! List) {
        return false;
      }
      _payloadUsed = (decoded['used'] as num?)?.toInt() ?? 0;
      _allocated = (decoded['capacity'] as num?)?.toInt() ?? file.lengthSync();
      _entries = [
        for (final item in files)
          if (item is Map)
            _Entry(
              name: item['n'] as String? ?? '',
              offset: (item['o'] as num?)?.toInt() ?? 0,
              length: (item['l'] as num?)?.toInt() ?? 0,
            ),
      ]..removeWhere((entry) => entry.name.isEmpty || entry.length < 0);
      return true;
    } on Object {
      return false;
    }
  }

  void _create() {
    final handle = file.openSync(mode: FileMode.write);
    try {
      final zeros = Uint8List(_chunk);
      var remaining = capacity;
      while (remaining > 0) {
        final n = remaining < _chunk ? remaining : _chunk;
        if (n == _chunk) {
          handle.writeFromSync(zeros);
        } else {
          handle.writeFromSync(zeros, 0, n);
        }
        remaining -= n;
      }
    } finally {
      handle.closeSync();
    }
    _entries = [];
    _payloadUsed = 0;
    _allocated = capacity;
    _cache.clear();
    _writeIndex();
  }

  void _writePayload(int offset, Uint8List data) {
    final end = payloadStart + offset + data.length;
    if (end > allocatedBytes) {
      throw StampVaultFullException();
    }
    _writeAt(payloadStart + offset, data);
  }

  void _writeAt(int offset, Uint8List data) {
    final handle = file.openSync(mode: FileMode.append);
    try {
      handle.setPositionSync(offset);
      handle.writeFromSync(data);
      handle.flushSync();
    } finally {
      handle.closeSync();
    }
  }

  void _writeIndex() {
    final files = [
      for (final entry in _entries)
        {'n': entry.name, 'o': entry.offset, 'l': entry.length},
    ];
    final sidecarJson = jsonEncode({
      'used': _payloadUsed,
      'capacity': allocatedBytes,
      'files': files,
    });
    final tmp = File('${_sidecar.path}.tmp');
    tmp.writeAsStringSync(sidecarJson, flush: true);
    tmp.renameSync(_sidecar.path);

    final indexBytes = Uint8List.fromList(utf8.encode(jsonEncode(files)));
    if (indexBytes.length > payloadStart - _headerSize) {
      throw StampVaultException('Занадто багато файлів у сховищі печаток.');
    }
    final header = ByteData(_headerSize);
    header.buffer.asUint8List().setRange(0, 4, _magic);
    header.setUint32(4, _version, Endian.little);
    header.setUint64(8, allocatedBytes, Endian.little);
    header.setUint32(16, payloadStart, Endian.little);
    header.setUint64(20, _payloadUsed, Endian.little);
    header.setUint32(28, indexBytes.length, Endian.little);

    final block = Uint8List(payloadStart);
    block.setRange(0, _headerSize, header.buffer.asUint8List(0, _headerSize));
    block.setRange(
      _headerSize,
      _headerSize + indexBytes.length,
      indexBytes,
    );
    _writeAt(0, block);
  }

  _Entry? _find(String name) {
    final needle = name.toLowerCase();
    for (final entry in _entries) {
      if (entry.name.toLowerCase() == needle) {
        return entry;
      }
    }
    return null;
  }
}
