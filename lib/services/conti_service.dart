import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conti.dart';

class ContiService {
  static final instance = ContiService._();
  ContiService._();

  static const _key = 'contis_v1';
  late SharedPreferences _prefs;

  final contis = ValueNotifier<List<Conti>>([]);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    final list = jsonDecode(raw) as List;
    contis.value = list
        .map((e) => Conti.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode(contis.value.map((c) => c.toJson()).toList()),
    );
  }

  Future<Conti> create(String title, List<String> songIds) async {
    final c = Conti(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      createdAt: DateTime.now(),
      songIds: List.from(songIds),
    );
    contis.value = [c, ...contis.value];
    await _save();
    return c;
  }

  Future<void> update(String id, {String? title, List<String>? songIds}) async {
    final list = contis.value.toList();
    final idx = list.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    if (title != null) list[idx].title = title;
    if (songIds != null) list[idx].songIds = List.from(songIds);
    contis.value = List.from(list);
    await _save();
  }

  Future<void> delete(String id) async {
    contis.value = contis.value.where((c) => c.id != id).toList();
    await _save();
  }
}
