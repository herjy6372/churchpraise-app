import 'package:churchpraise/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 백업 크기는 필드 이름과 값의 UTF-8 바이트로 계산', () {
    expect(SyncService.estimateBackupBytes({'a': 'bc'}), 1 + 2 + 1);
    // 한글은 한 글자에 3바이트
    expect(SyncService.estimateBackupBytes({'k': '가나'}), 1 + 6 + 1);
  });

  test('한도를 넘는 필기 데이터는 서버 백업 전에 걸러냄', () {
    final small = {'annotations': 'x' * 1000};
    final big = {'annotations': 'x' * (SyncService.maxServerBackupBytes + 1)};
    expect(SyncService.estimateBackupBytes(small) <= SyncService.maxServerBackupBytes, isTrue);
    expect(SyncService.estimateBackupBytes(big) > SyncService.maxServerBackupBytes, isTrue);
    // Firestore 문서 한도(1MiB)보다 작게 잡아 서버 거절 전에 안내
    expect(SyncService.maxServerBackupBytes < 1048576, isTrue);
  });

  test('너무 크면 파일로 백업을 안내하는 문구', () {
    final msg = const BackupTooLargeException(1572864).toString();
    expect(msg, contains('1.5MB'));
    expect(msg, contains('파일로 백업'));
  });
}
