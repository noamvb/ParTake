import 'package:parlvu/parlvu.dart';

class CaptionHit {
  const CaptionHit(this.caption, this.index);
  final Caption caption;
  final int index;
}

class CaptionIndex {
  CaptionIndex(List<Caption> captions) : captions = List.unmodifiable(captions);
  final List<Caption> captions;

  Caption? at(DateTime wallClock) {
    var low = 0;
    var high = captions.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (captions[mid].begin.compareTo(wallClock) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final index = low - 1;
    if (index < 0) return null;
    final caption = captions[index];
    return wallClock.isBefore(caption.end.add(const Duration(seconds: 2)))
        ? caption
        : null;
  }

  List<CaptionHit> search(String query) {
    final needle = _normalize(query).toLowerCase();
    if (needle.length < 2) return const [];
    final hits = <CaptionHit>[];
    for (var i = 0; i < captions.length && hits.length < 200; i++) {
      final one = _normalize(captions[i].text).toLowerCase();
      final two = i + 1 < captions.length
          ? '$one ${_normalize(captions[i + 1].text).toLowerCase()}'
          : one;
      if (two.contains(needle)) hits.add(CaptionHit(captions[i], i));
    }
    return hits;
  }

  static String _normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');
}
