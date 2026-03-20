import 'dart:convert';

import 'package:check_var/core/api/gemini_scam_text_api.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'classifyTranscriptWindow parses schema-constrained scam results',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'threat_level': 'scam',
                        'confidence': 0.92,
                        'patterns_detected': ['gia mao', 'the qua tang'],
                        'summary':
                            'Nguoi goi gia danh ngan hang va yeu cau mua the qua tang',
                        'advice': 'Tat may va goi lai ngan hang bang so chinh thuc',
                      }),
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final api = GeminiScamTextApi(client: client, apiKey: 'key');
      final result = await api.classifyTranscriptWindow(
        'Tai khoan cua ban da bi khoa. Hay mua the qua tang ngay lap tuc.',
      );

      expect(result.threatLevel, ThreatLevel.scam);
      expect(result.patterns, contains('the qua tang'));
    },
  );
}
