import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_settings.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _VersionStatus { loading, latest, updateAvailable, unknown }

class _SettingsScreenState extends State<SettingsScreen> {
  DateTime? _lastBackup;
  bool _loadingBackupTime = true;
  _VersionStatus _versionStatus = _VersionStatus.loading;
  String? _storeVersion;

  static const _playStoreId = 'com.terablack.churchpraise';

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
    _checkLatestVersion();
  }

  Future<void> _checkLatestVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      // Play Store 페이지 스크래핑 (모바일 UA + 복수 패턴)
      final urls = [
        'https://play.google.com/store/apps/details?id=$_playStoreId&hl=en&gl=US',
        'https://play.google.com/store/apps/details?id=$_playStoreId&hl=ko&gl=KR',
      ];
      for (final rawUrl in urls) {
        final response = await http.get(Uri.parse(rawUrl), headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        }).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) continue;

        final body = response.body;
        final patterns = [
          // 2024+ Play Store JSON 데이터 블록
          RegExp(r'\[\[\["(\d+\.\d+\.\d+(?:\.\d+)?)"\]\]'),
          RegExp(r'"(\d+\.\d+\.\d+(?:\.\d+)?)",null,\['),
          // 구버전 패턴
          RegExp(r'"softwareVersion":"(\d+\.\d+\.\d+(?:\.\d+)?)"'),
          RegExp(r'Current Version</div><div[^>]*>(\d+\.\d+\.\d+(?:\.\d+)?)'),
        ];
        String? latest;
        for (final pattern in patterns) {
          final match = pattern.firstMatch(body);
          if (match != null) {
            latest = match.group(1);
            break;
          }
        }
        if (latest != null && mounted) {
          final isLatest = _compareVersions(current, latest) >= 0;
          setState(() {
            _storeVersion = latest;
            _versionStatus =
                isLatest ? _VersionStatus.latest : _VersionStatus.updateAvailable;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _versionStatus = _VersionStatus.unknown);
  }

  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(int.tryParse).toList();
    final bParts = b.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? (aParts[i] ?? 0) : 0;
      final bv = i < bParts.length ? (bParts[i] ?? 0) : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  Future<void> _loadLastBackup() async {
    final t = await SyncService.instance.lastBackupTime();
    if (mounted) setState(() { _lastBackup = t; _loadingBackupTime = false; });
  }

  String _formatBackupTime(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildVersionTrailing(ColorScheme cs, String version) {
    switch (_versionStatus) {
      case _VersionStatus.loading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(version, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(width: 8),
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
          ],
        );
      case _VersionStatus.latest:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(version, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 12, color: Colors.green.shade600),
                  const SizedBox(width: 3),
                  Text('최신 버전', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        );
      case _VersionStatus.updateAvailable:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(version, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update, size: 12, color: Colors.orange.shade700),
                  const SizedBox(width: 3),
                  Text(
                    _storeVersion != null ? '${_storeVersion!} 업데이트' : '업데이트 있음',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        );
      case _VersionStatus.unknown:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(version, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() => _versionStatus = _VersionStatus.loading);
                _checkLatestVersion();
              },
              child: Icon(Icons.refresh, size: 16, color: cs.onSurface.withValues(alpha: 0.45)),
            ),
          ],
        );
    }
  }

  Future<void> _handleSignIn() async {
    try {
      await SyncService.instance.signInWithGoogle();
      if (mounted) {
        setState(() {});
        _loadLastBackup();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    }
  }

  Future<void> _handleBackup() async {
    try {
      await SyncService.instance.backup();
      await _loadLastBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업 완료!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('백업 실패: $e')),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('데이터 복원'),
        content: const Text('현재 기기의 데이터가 백업 데이터로 덮어씌워집니다. 계속하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('복원')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SyncService.instance.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원 완료!')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복원 실패: $e')),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    await SyncService.instance.signOut();
    if (mounted) setState(() { _lastBackup = null; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.hasData
              ? '${snap.data!.version} (빌드 ${snap.data!.buildNumber})'
              : '불러오는 중...';
          return ValueListenableBuilder<User?>(
            valueListenable: SyncService.instance.currentUser,
            builder: (context, user, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: SyncService.instance.syncing,
                builder: (context, isSyncing, _) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    children: [
                      // ── 테마 ──
                      _SectionHeader(title: '일반'),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.palette_outlined),
                          title: const Text('테마'),
                          trailing: ValueListenableBuilder<ThemeMode>(
                            valueListenable: AppSettings.instance.themeMode,
                            builder: (context, mode, _) => TextButton(
                              onPressed: AppSettings.instance.cycleTheme,
                              child: Text(AppSettings.instance.themeLabel),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── 계정 / 동기화 ──
                      _SectionHeader(title: '계정 및 동기화'),
                      if (user == null)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.login),
                            title: const Text('Google 로그인'),
                            subtitle: const Text('로그인하면 데이터를 백업/복원할 수 있습니다'),
                            onTap: _handleSignIn,
                          ),
                        )
                      else ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundImage: user.photoURL != null
                                          ? NetworkImage(user.photoURL!)
                                          : null,
                                      child: user.photoURL == null
                                          ? const Icon(Icons.person, size: 22)
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(user.displayName ?? '사용자',
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                          Text(user.email ?? '',
                                              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _handleSignOut,
                                      child: const Text('로그아웃'),
                                    ),
                                  ],
                                ),
                                if (!_loadingBackupTime && _lastBackup != null) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, size: 14, color: cs.onSurface.withValues(alpha: 0.5)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '마지막 백업: ${_formatBackupTime(_lastBackup!)}',
                                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: isSyncing ? null : _handleBackup,
                                        icon: isSyncing
                                            ? const SizedBox(width: 16, height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                                        label: const Text('백업'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: isSyncing ? null : _handleRestore,
                                        icon: const Icon(Icons.cloud_download_outlined, size: 18),
                                        label: const Text('복원'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── 앱 정보 ──
                      _SectionHeader(title: '앱 정보'),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.music_note_outlined),
                              title: const Text('앱 이름'),
                              trailing: Text('성경&찬양',
                                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                            ),
                            Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                            ListTile(
                              leading: const Icon(Icons.info_outline),
                              title: const Text('앱 버전'),
                              trailing: _buildVersionTrailing(cs, version),
                              onTap: _versionStatus == _VersionStatus.updateAvailable
                                  ? () async {
                                      final uri = Uri.parse(
                                          'https://play.google.com/store/apps/details?id=$_playStoreId');
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  : null,
                            ),
                            Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                            ListTile(
                              leading: const Icon(Icons.privacy_tip_outlined),
                              title: const Text('개인정보처리방침'),
                              trailing: const Icon(Icons.open_in_new, size: 18),
                              onTap: () async {
                                final uri = Uri.parse('https://herjy6372.github.io/churchpraise/privacy_policy.html');
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}
