import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'favorites_service.dart';
import 'conti_service.dart';
import 'tag_service.dart';
import 'highlight_service.dart';
import 'reading_plan_service.dart';

/// 서버 백업 데이터가 Firestore 문서 한 개의 크기 한도를 넘을 때
class BackupTooLargeException implements Exception {
  final int bytes;
  const BackupTooLargeException(this.bytes);
  @override
  String toString() =>
      '백업 데이터가 너무 커서 서버에 저장할 수 없습니다 (약 ${(bytes / 1024 / 1024).toStringAsFixed(1)}MB). '
      '설정의 \'파일로 백업\'을 이용해 주세요.';
}

class SyncService {
  static final instance = SyncService._();
  SyncService._();

  final currentUser = ValueNotifier<User?>(null);
  final syncing = ValueNotifier<bool>(false);

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  static const _annoPrefix = 'anno_v1_';

  /// Firestore 문서 한 개의 한도는 1MiB(1,048,576바이트). 필드 이름·메타데이터 몫을 남겨 두고 이보다 크면 미리 막는다.
  static const maxServerBackupBytes = 1000 * 1000;

  /// 서버에 올릴 문서 크기를 대략 계산 (필드 이름 + 값의 UTF-8 바이트 수)
  static int estimateBackupBytes(Map<String, String> fields) {
    var total = 0;
    for (final e in fields.entries) {
      total += utf8.encode(e.key).length + utf8.encode(e.value).length + 1;
    }
    return total;
  }

  void init() {
    GoogleSignIn.instance.initialize(
      clientId: '870682092391-e4aiclj6e17tcgdf4scbb6jce4sfm9o0.apps.googleusercontent.com',
      serverClientId: '870682092391-8a5u87o9h666tukgrpe8co1ipi9r56oh.apps.googleusercontent.com',
    );
    _auth.authStateChanges().listen((user) {
      currentUser.value = user;
    });
  }

  Future<User?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn.instance.authenticate();
    final idToken = googleUser.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.disconnect();
    await _auth.signOut();
  }

  DocumentReference _userDoc() {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('users').doc(uid);
  }

  Future<void> backup() async {
    if (_auth.currentUser == null) return;
    syncing.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // 즐겨찾기
      final favRaw = prefs.getString('favorites_v2') ?? '{}';

      // 콘티
      final contiRaw = prefs.getString('contis_v1') ?? '[]';

      // 태그
      final tagRaw = prefs.getString('song_tags_v2') ?? '{}';

      // 필기 데이터
      final annoMap = <String, String>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_annoPrefix)) {
          final val = prefs.getString(key);
          if (val != null) annoMap[key] = val;
        }
      }

      // 성경 형광펜, 성경읽기표 진도
      final highlightRaw = prefs.getString(HighlightService.prefKey) ?? '{}';
      final readingRaw = prefs.getString(ReadingPlanService.prefKey) ?? '[]';

      final email = _auth.currentUser!.email ?? '';
      final fields = <String, String>{
        'favorites': favRaw,
        'contis': contiRaw,
        'tags': tagRaw,
        'bibleHighlights': highlightRaw,
        'readingPlan2027': readingRaw,
        'annotations': jsonEncode(annoMap),
        'email': email,
      };
      final size = estimateBackupBytes(fields);
      if (size > maxServerBackupBytes) throw BackupTooLargeException(size);

      try {
        await _userDoc().set({
          ...fields,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        // 계산보다 실제 문서가 커서 서버가 거절한 경우도 같은 안내로
        if (e.code == 'invalid-argument' &&
            (e.message ?? '').toLowerCase().contains('exceeds')) {
          throw BackupTooLargeException(size);
        }
        rethrow;
      }
    } finally {
      syncing.value = false;
    }
  }

  Future<void> restore() async {
    if (_auth.currentUser == null) return;
    syncing.value = true;
    try {
      final snap = await _userDoc().get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();

      // 즐겨찾기
      if (data['favorites'] != null) {
        await prefs.setString('favorites_v2', data['favorites'] as String);
        await FavoritesService.instance.init();
      }

      // 콘티
      if (data['contis'] != null) {
        await prefs.setString('contis_v1', data['contis'] as String);
        await ContiService.instance.init();
      }

      // 태그
      if (data['tags'] != null) {
        await prefs.setString('song_tags_v2', data['tags'] as String);
        await TagService.instance.init();
      }

      // 성경 형광펜, 성경읽기표 진도
      if (data['bibleHighlights'] != null) {
        await prefs.setString(
            HighlightService.prefKey, data['bibleHighlights'] as String);
        await HighlightService.instance.init();
      }
      if (data['readingPlan2027'] != null) {
        await prefs.setString(
            ReadingPlanService.prefKey, data['readingPlan2027'] as String);
        await ReadingPlanService.instance.init();
      }

      // 필기 데이터
      if (data['annotations'] != null) {
        final annoMap = jsonDecode(data['annotations'] as String) as Map<String, dynamic>;
        for (final entry in annoMap.entries) {
          await prefs.setString(entry.key, entry.value as String);
        }
      }
    } finally {
      syncing.value = false;
    }
  }

  Future<DateTime?> lastBackupTime() async {
    if (_auth.currentUser == null) return null;
    try {
      final snap = await _userDoc().get();
      if (!snap.exists) return null;
      final data = snap.data() as Map<String, dynamic>;
      final ts = data['updatedAt'] as Timestamp?;
      return ts?.toDate();
    } catch (_) {
      return null;
    }
  }
}
