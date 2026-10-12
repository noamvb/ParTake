import 'dart:convert';
import 'dart:io';

Map<String, dynamic> pollsSeam(String name) =>
    jsonDecode(File('test/polls/${name}_seam.json').readAsStringSync())
        as Map<String, dynamic>;

/// P2 predates odds, comparisons and weekly notes.
Map<String, dynamic> p2SummarySeam() {
  final seam = pollsSeam('summary');
  for (final field in ['majority', 'minority', 'comparison', 'note']) {
    seam[field] = null;
  }
  for (final range in (seam['seats'] as Map).values) {
    range['low'] = range['high'] = range['median'];
  }
  return seam;
}

/// The three-riding literal covers safe, likely and at-risk; this variant
/// covers the fourth holder status without increasing that fixture's size.
Map<String, dynamic> projectedLossSeam() {
  final seam = pollsSeam('ridings');
  final riding = (seam['ridings'] as List).singleWhere(
    (r) => r['id'] == '24038',
  );
  riding['status'] = 'projected_loss';
  riding['projected'] = 'CPC';
  riding['mp']['party'] = 'LPC';
  return seam;
}
