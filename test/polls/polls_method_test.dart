import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:partake/polls/polls_method.dart';

void main() {
  test('Method matches METHOD.md section by section and block by block', () {
    final source = File('docs/polls/METHOD.md').readAsStringSync();
    final sections = source
        .substring(source.indexOf('## What it shows'))
        .split(RegExp(r'^## ', multiLine: true))
        .skip(1)
        .map((section) {
          final lines = section.trim().split('\n');
          final blocks = lines.skip(1).join('\n').trim().split('\n\n');
          return {
            'title': lines.first,
            'blocks': blocks.map((block) {
              if (block.startsWith('- ')) {
                return block
                    .split(RegExp(r'^- ', multiLine: true))
                    .skip(1)
                    .map(
                      (item) => item
                          .trim()
                          .split('\n')
                          .map((line) => line.trim())
                          .join(' ')
                          .replaceAll('**', ''),
                    )
                    .toList();
              }
              return block.split('\n').join(' ').replaceAll('**', '');
            }).toList(),
          };
        })
        .toList();
    final actual = pollsMethod
        .map(
          (section) => {
            'title': section.title,
            'blocks': section.blocks
                .map(
                  (block) =>
                      block.paragraph ??
                      block.bullets
                          .map((bullet) => '${bullet.label}${bullet.text}')
                          .toList(),
                )
                .toList(),
          },
        )
        .toList();
    expect(actual, sections);
    final labelled = pollsMethod
        .expand((s) => s.blocks)
        .expand((b) => b.bullets)
        .where((b) => b.label.isNotEmpty);
    expect(labelled.map((b) => b.label), [
      'Safe',
      'Likely',
      'At risk',
      'Projected loss',
    ]);
    expect(labelled.every((b) => b.bold), isTrue);
  });
}
