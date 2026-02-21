import 'package:flutter_test/flutter_test.dart';
import 'package:drishti/core/voice_utils.dart';

void main() {
  group('VoiceUtils.normalizeToEnglish', () {
    test('English simple', () {
      expect(VoiceUtils.normalizeToEnglish('Hello'), 'hello');
    });

    test('Hindi transliteration', () {
      expect(VoiceUtils.normalizeToEnglish('नमन'), 'naman');
      expect(VoiceUtils.normalizeToEnglish('अमित'), 'amit');
    });

    test('Marathi transliteration', () {
      expect(VoiceUtils.normalizeToEnglish('नंदिनी'), 'nandinee');
    });

    test('Strips numbers and spaces', () {
      expect(VoiceUtils.normalizeToEnglish('Naman 123'), 'naman');
    });

    test('Complex Hindi with mixed symbols', () {
      expect(VoiceUtils.normalizeToEnglish('अमित @ # 456'), 'amit');
    });

    test('Empty input', () {
      expect(VoiceUtils.normalizeToEnglish(''), '');
    });
  });
}
