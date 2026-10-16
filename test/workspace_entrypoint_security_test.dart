import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening the workspace cannot start repository tasks', () {
    final settings =
        jsonDecode(File('.vscode/settings.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(settings['task.allowAutomaticTasks'], 'off');
    expect(settings.containsKey('tasks'), isFalse);

    final tasks =
        jsonDecode(File('.vscode/tasks.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final task in tasks['tasks'] as List<dynamic>) {
      expect(
        (task as Map<String, dynamic>)['runOptions']?['runOn'],
        isNot('folderOpen'),
      );
    }
  });

  test('public font binaries have their declared format signatures', () {
    final signatures = <String, List<int>>{
      '.woff': [0x77, 0x4f, 0x46, 0x46],
      '.woff2': [0x77, 0x4f, 0x46, 0x32],
      '.ttf': [0, 1, 0, 0],
      '.otf': [0x4f, 0x54, 0x54, 0x4f],
    };
    for (final file in Directory('public/fonts').listSync().whereType<File>()) {
      final bytes = file.readAsBytesSync();
      for (final entry in signatures.entries) {
        if (file.path.endsWith(entry.key)) {
          expect(
            bytes.take(entry.value.length),
            orderedEquals(entry.value),
            reason: file.path,
          );
        }
      }
      if (file.path.endsWith('.eot')) {
        // EOT's fixed header magic is LP at offset 34. Script text hidden under
        // a font suffix must fail before any tool tries to open or execute it.
        expect(bytes.length, greaterThan(35), reason: file.path);
        expect(
          bytes.sublist(34, 36),
          orderedEquals([0x4c, 0x50]),
          reason: file.path,
        );
      }
    }
  });
}
