import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static final instance = FavoritesService._();
  FavoritesService._();

  static const _key = 'favorites_v2';

  late SharedPreferences _prefs;

  // Map<songId (e.g. "h_45" or "c_1"), DateTime>
  final favorites = ValueNotifier<Map<String, DateTime>>({});

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
    await _migrateOldFormat();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    favorites.value = map.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
  }

  // Migrate old format: bare int keys "45" → "h_45"
  Future<void> _migrateOldFormat() async {
    final oldRaw = _prefs.getString('favorites');
    if (oldRaw == null) return;
    try {
      final old = jsonDecode(oldRaw) as Map<String, dynamic>;
      if (old.isEmpty) return;
      final current = Map<String, DateTime>.from(favorites.value);
      for (final entry in old.entries) {
        final newKey = 'h_${entry.key}';
        current.putIfAbsent(newKey, () => DateTime.parse(entry.value as String));
      }
      favorites.value = current;
      await _save();
      await _prefs.remove('favorites');
    } catch (_) {}
  }

  Future<void> toggle(String songId) async {
    final current = Map<String, DateTime>.from(favorites.value);
    if (current.containsKey(songId)) {
      current.remove(songId);
    } else {
      current[songId] = DateTime.now();
    }
    favorites.value = current;
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode(favorites.value.map((k, v) => MapEntry(k, v.toIso8601String()))),
    );
  }

  bool isFavorite(String songId) => favorites.value.containsKey(songId);

  DateTime? addedDate(String songId) => favorites.value[songId];

  String formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '오늘';
    if (diff.inDays == 1) return '어제';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${date.month}월 ${date.day}일';
  }

  List<String> sortedByDate({String? prefix}) {
    var entries = favorites.value.entries.toList();
    if (prefix != null) entries = entries.where((e) => e.key.startsWith(prefix)).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }
}
