import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/features/scam_call/speaker_test/phrase_accuracy.dart';

void main() {
  group('scorePhraseAccuracy', () {
    test('perfect match after lowercasing and stripping punctuation', () {
      final result = scorePhraseAccuracy(
        expected: 'Vui long xac nhan so tai khoan',
        recognized: 'vui long xac nhan so tai khoan!',
      );

      expect(result.matchedWords, 7);
      expect(result.expectedWords, 7);
      expect(result.accuracy, 1.0);
      expect(result.verdict, SpeakerTestVerdict.usable);
    });

    test('partial match scores as borderline', () {
      final result = scorePhraseAccuracy(
        expected: 'chuyen tien ngay lap tuc',
        recognized: 'chuyen tien ngay',
      );

      expect(result.accuracy, 0.6);
      expect(result.verdict, SpeakerTestVerdict.borderline);
    });

    test('poor match scores as not usable', () {
      final result = scorePhraseAccuracy(
        expected: 'chung toi can so can cuoc cong dan cua ban',
        recognized: 'xin chao',
      );

      expect(result.accuracy, lessThan(0.5));
      expect(result.verdict, SpeakerTestVerdict.notUsable);
    });

    test('empty recognized text scores zero', () {
      final result = scorePhraseAccuracy(
        expected: 'gui khoan thanh toan ngay lap tuc',
        recognized: '',
      );

      expect(result.accuracy, 0.0);
      expect(result.verdict, SpeakerTestVerdict.notUsable);
    });

    test('empty expected text scores zero', () {
      final result = scorePhraseAccuracy(
        expected: '',
        recognized: 'mot vai tu',
      );

      expect(result.accuracy, 0.0);
    });

    test('preserves Vietnamese single-letter words during scoring', () {
      final result = scorePhraseAccuracy(
        expected: 'o nha',
        recognized: 'o',
      );

      expect(result.matchedWords, 1);
      expect(result.expectedWords, 2);
      expect(result.accuracy, 0.5);
      expect(result.verdict, SpeakerTestVerdict.borderline);
    });

    test('scores Vietnamese phrase correctly', () {
      final result = scorePhraseAccuracy(
        expected: 'vui long xac nhan so tai khoan',
        recognized: 'vui long xac nhan so tai khoan',
      );

      expect(result.accuracy, 1.0);
      expect(result.verdict, SpeakerTestVerdict.usable);
    });

    test('handles partial Vietnamese recognition', () {
      final result = scorePhraseAccuracy(
        expected: 'chuyen tien ngay lap tuc',
        recognized: 'chuyen tien ngay',
      );

      expect(result.matchedWords, 3);
      expect(result.expectedWords, 5);
    });
  });

  group('overallVerdict', () {
    test('returns usable when average accuracy >= 0.8', () {
      expect(overallVerdict(0.85), SpeakerTestVerdict.usable);
    });

    test('returns borderline when average accuracy >= 0.5', () {
      expect(overallVerdict(0.65), SpeakerTestVerdict.borderline);
    });

    test('returns notUsable when average accuracy < 0.5', () {
      expect(overallVerdict(0.3), SpeakerTestVerdict.notUsable);
    });
  });
}
