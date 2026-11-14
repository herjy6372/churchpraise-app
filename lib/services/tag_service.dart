import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/hymn_data.dart';

class TagService {
  static final instance = TagService._();
  TagService._();

  static const _key = 'song_tags_v2';
  static const _initKey = 'song_tags_v2_init';
  static const _initKeyV3 = 'song_tags_v3_init';
  static const _initKeyV4 = 'song_tags_v4_init';
  static const _initKeyV5 = 'song_tags_v5_init';
  static const _initKeyV6 = 'song_tags_v6_init';
  static const _initKeyV7 = 'song_tags_v7_init';
  static const _initKeyV8 = 'song_tags_v8_init';
  static const _initKeyV9 = 'song_tags_v9_init';
  static const _timeSignatureSyncKey = 'song_tags_ts_sync';

  late SharedPreferences _prefs;

  // Map<songId, Map<category, value>>
  final tags = ValueNotifier<Map<String, Map<String, String>>>({});

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
    await _applyDefaults();
    await _applyDefaultsV3();
    await _applyDefaultsV4();
    await _applyDefaultsV5();
    await _applyDefaultsV6();
    await _applyDefaultsV7();
    await _applyDefaultsV8();
    await _applyDefaultsV9();
    await _syncTimeSignatures();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    final outer = jsonDecode(raw) as Map<String, dynamic>;
    tags.value = outer.map(
      (songId, inner) => MapEntry(
        songId,
        (inner as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String)),
      ),
    );
  }

  // Load HymnData.timeSignatures as default 박자 tags (first launch only)
  Future<void> _applyDefaults() async {
    if (_prefs.getBool(_initKey) == true) return;
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in HymnData.timeSignatures.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKey, true);
  }

  // Apply correct time signature tags for hymns 1~8 (migration v3)
  Future<void> _applyDefaultsV3() async {
    if (_prefs.getBool(_initKeyV3) == true) return;
    const newSigs = {1: '4/4', 2: '6/4', 3: '4/4', 4: '4/4', 5: '4/4', 6: '4/4', 7: '4/2', 8: '4/4'};
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in newSigs.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV3, true);
  }

  // Definitive fix: apply correct 박자 tags for hymns 1~8
  Future<void> _applyDefaultsV4() async {
    if (_prefs.getBool(_initKeyV4) == true) return;
    const sigs = {1: '4/4', 2: '6/4', 3: '4/4', 4: '4/4', 5: '4/4', 6: '4/4', 7: '4/2', 8: '4/4'};
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in sigs.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV4, true);
  }

  // Apply 박자 tags for hymns 9~40 (and fix 10장 to 3/4)
  Future<void> _applyDefaultsV5() async {
    if (_prefs.getBool(_initKeyV5) == true) return;
    const sigs = {
      9: '3/4', 10: '3/4', 11: '3/4', 12: '4/4', 13: '4/4',
      14: '4/4', 15: '4/4', 16: '4/4', 17: '3/4', 18: '4/4',
      19: '3/4', 20: '3/4', 21: '3/4', 22: '4/4', 23: '3/2',
      24: '4/4', 26: '4/4', 27: '6/4', 28: '3/4', 29: '4/4',
      30: '4/4', 31: '6/8', 32: '4/4', 33: '4/4', 34: '3/4',
      35: '4/4', 36: '4/4', 37: '3/4', 38: '2/2', 39: '3/4', 40: '4/4',
    };
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in sigs.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV5, true);
  }

    // 41~50장 박자 태그 + 45장 수정(3/4→6/8)
  Future<void> _applyDefaultsV6() async {
    if (_prefs.getBool(_initKeyV6) == true) return;
    const sigs = {
      41: '4/4', 42: '4/4', 43: '4/4', 44: '3/4',
      45: '6/8', 46: '3/2', 47: '6/8',
      48: '3/4', 49: '4/4', 50: '4/4',
    };
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in sigs.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV6, true);
  }

  // CCM 곡 박자 태그: 오 신실하신 주, 실로암, 주님 다시 오실 때까지 + 찬송가 51~52장
  Future<void> _applyDefaultsV7() async {
    if (_prefs.getBool(_initKeyV7) == true) return;
    const ccmSigs = {
      'c_5': '4/4', 'c_6': '4/4', 'c_7': '4/4', 'c_8': '4/4',
      'c_9': '4/4', 'c_10': '4/4', 'c_11': '4/4', 'c_12': '4/4',
      'c_13': '4/4', 'c_14': '4/4', 'c_15': '4/4', 'c_16': '4/4',
      'c_17': '4/4',
      'c_18': '4/4',
      'c_19': '4/4',
      'c_20': '2/2',
    };
    const hymnSigs = {
      51: '6/8', 52: '3/4', 53: '3/4', 54: '4/4', 55: '4/4',
      56: '2/2', 57: '2/2', 58: '4/4', 59: '4/4', 60: '3/4',
      61: '4/4', 62: '3/4', 63: '4/4', 64: '4/4', 65: '2/4',
      66: '4/4', 67: '3/4', 68: '3/4', 69: '3/2', 70: '3/4',
      71: '4/4', 72: '4/4', 73: '2/2', 74: '6/4', 75: '3/4',
      76: '3/4', 77: '4/4', 78: '4/4', 79: '4/4', 80: '3/4',
      81: '4/4', 82: '6/4', 83: '4/4', 84: '6/8', 85: '3/4',
      86: '4/4', 87: '6/4', 88: '4/4', 89: '3/4', 90: '3/4',
      91: '4/4', 92: '3/4', 93: '6/8', 94: '3/4', 95: '4/4',
      96: '4/4', 97: '4/4', 98: '3/4', 99: '2/2', 100: '3/4',
      101: '2/2', 102: '2/2', 103: '4/4', 104: '4/4',
      266: '3/4', 360: '4/4',
    };
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in ccmSigs.entries) {
      current[entry.key] = {...(current[entry.key] ?? {}), '박자': entry.value};
    }
    for (final entry in hymnSigs.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV7, true);
  }

  // V8: 51~104장 + CCM 박자 태그 재적용 (V7이 이미 실행된 기기용)
  Future<void> _applyDefaultsV8() async {
    if (_prefs.getBool(_initKeyV8) == true) return;
    const hymnSigs = {
      51: '6/8', 52: '3/4', 53: '3/4', 54: '4/4', 55: '4/4',
      56: '2/2', 57: '2/2', 58: '4/4', 59: '4/4', 60: '3/4',
      61: '4/4', 62: '3/4', 63: '4/4', 64: '4/4', 65: '2/4',
      66: '4/4', 67: '3/4', 68: '3/4', 69: '3/2', 70: '3/4',
      71: '4/4', 72: '4/4', 73: '2/2', 74: '6/4', 75: '3/4',
      76: '3/4', 77: '4/4', 78: '4/4', 79: '4/4', 80: '3/4',
      81: '4/4', 82: '6/4', 83: '4/4', 84: '6/8', 85: '3/4',
      86: '4/4', 87: '6/4', 88: '4/4', 89: '3/4', 90: '3/4',
      91: '4/4', 92: '3/4', 93: '6/8', 94: '3/4', 95: '4/4',
      96: '4/4', 97: '4/4', 98: '3/4', 99: '2/2', 100: '3/4',
      101: '2/2', 102: '2/2', 103: '4/4', 104: '4/4',
      105: '3/4', 106: '2/4', 107: '4/4', 108: '3/4', 109: '6/8',
      110: '4/4', 111: '6/8', 112: '6/8', 113: '6/8', 114: '3/4',
      115: '2/4', 116: '3/8', 117: '4/4', 118: '4/4', 119: '4/2',
      120: '4/4', 121: '6/8', 122: '4/4', 123: '3/4', 124: '4/4',
      125: '4/4', 126: '4/4', 127: '4/4', 128: '3/4', 129: '2/2',
      130: '3/4', 131: '3/4', 132: '4/4', 134: '6/8', 135: '6/8',
      136: '4/4', 137: '6/8', 138: '2/2', 139: '4/4', 140: '4/4',
      141: '4/4', 142: '3/4', 143: '3/4', 144: '6/8', 145: '4/4',
      146: '6/8', 147: '4/4', 148: '4/4', 149: '4/4', 150: '6/8',
      151: '4/4', 152: '4/4', 153: '6/8', 154: '4/4', 155: '3/4',
      156: '3/4', 157: '6/8', 158: '9/8', 159: '3/4', 160: '4/4',
      161: '3/4', 162: '6/8', 163: '6/4', 164: '4/4', 165: '4/4',
      166: '3/4', 167: '4/4', 168: '9/4', 169: '4/4', 170: '3/4',
      171: '4/4', 172: '3/2', 173: '2/2', 174: '3/4', 175: '4/4',
      176: '4/4', 177: '4/4', 178: '4/4', 179: '4/4', 180: '4/4',
      266: '3/4', 270: '4/4', 360: '4/4', 449: '3/4',
    };
    const ccmSigs = {
      'c_5': '4/4', 'c_6': '4/4', 'c_7': '4/4', 'c_8': '4/4',
      'c_9': '4/4', 'c_10': '4/4', 'c_11': '4/4', 'c_12': '4/4',
      'c_13': '4/4', 'c_14': '4/4', 'c_15': '4/4', 'c_16': '4/4',
      'c_17': '4/4', 'c_18': '4/4', 'c_19': '4/4', 'c_20': '2/2',
      'c_21': '4/4', 'c_22': '4/4',
    };
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in hymnSigs.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    for (final entry in ccmSigs.entries) {
      current[entry.key] = {...(current[entry.key] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV8, true);
  }

  // V9: CCM c_23~c_27 박자 태그
  Future<void> _applyDefaultsV9() async {
    if (_prefs.getBool(_initKeyV9) == true) return;
    const ccmSigs = {
      'c_23': '4/4',
      'c_24': '4/4',
      'c_25': '4/4',
      'c_26': '12/8',
      'c_27': '4/4',
      'c_28': '4/4',
      'c_29': '4/4',
    };
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in ccmSigs.entries) {
      current[entry.key] = {...(current[entry.key] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setBool(_initKeyV9, true);
  }

  // HymnData.timeSignatures가 변경될 때마다 자동 반영
  Future<void> _syncTimeSignatures() async {
    final count = HymnData.timeSignatures.length;
    final lastSync = _prefs.getInt(_timeSignatureSyncKey) ?? 0;
    if (lastSync == count) return;
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    for (final entry in HymnData.timeSignatures.entries) {
      final id = 'h_${entry.key}';
      current[id] = {...(current[id] ?? {}), '박자': entry.value};
    }
    tags.value = current;
    await _save();
    await _prefs.setInt(_timeSignatureSyncKey, count);
  }

    String? getTag(String songId, String category) {
    return tags.value[songId]?[category];
  }

  Map<String, String> getTagsFor(String songId) {
    return Map.unmodifiable(tags.value[songId] ?? {});
  }

  Future<void> setTag(String songId, String category, String? value) async {
    final current = Map<String, Map<String, String>>.from(
      tags.value.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    if (value == null || value.isEmpty) {
      current[songId]?.remove(category);
      if (current[songId]?.isEmpty == true) current.remove(songId);
    } else {
      current[songId] = {...(current[songId] ?? {}), category: value};
    }
    tags.value = current;
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode(tags.value.map((k, v) => MapEntry(k, v))),
    );
  }
}
