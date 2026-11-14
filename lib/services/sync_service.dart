import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'favorites_service.dart';
import 'conti_service.dart';
import 'tag_service.dart';

class SyncService {
  static final instance = SyncService._();
  SyncService._();

  final currentUser = ValueNotifier<User?>(null);
  final syncing = ValueNotifier<bool>(false);

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  static const _annoPrefix = 'anno_v1_';

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

      await _userDoc().set({
        'favorites': favRaw,
        'contis': contiRaw,
        'tags': tagRaw,
        'annotations': jsonEncode(annoMap),
        'updatedAt': FieldValue.serverTimestamp(),
        'email': _auth.currentUser!.email,
      });
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
