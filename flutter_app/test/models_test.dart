import 'package:applemusicdecrypt_android/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a task snapshot', () {
    final snapshot = TaskSnapshot.fromJson({
      'tasks': [
        {
          'adamId': '123',
          'title': 'Song',
          'status': 'DOWNLOADING',
        },
      ],
      'downloadSpeed': '1.00 MB/s',
      'decryptSpeed': '2.00 MB/s',
      'running': 1,
    });

    expect(snapshot.tasks.single.title, 'Song');
    expect(snapshot.tasks.single.canCancel, isTrue);
    expect(snapshot.running, 1);
  });
}
