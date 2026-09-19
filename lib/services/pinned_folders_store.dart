import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class PinnedFoldersStore {
  static const _key = 'pinned_folders';

  Future<List<PinnedFolder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => PinnedFolder.fromJson(Map<String, dynamic>.from(item)))
        .where((folder) => folder.path.isNotEmpty)
        .toList();
  }

  Future<void> save(List<PinnedFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(folders.map((folder) => folder.toJson()).toList()),
    );
  }
}
