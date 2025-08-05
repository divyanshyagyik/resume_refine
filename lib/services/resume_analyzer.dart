import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';

class ResumeAnalyzer {
  static const _maxRetries = 3;
  static const _initialDelay = Duration(seconds: 2);

  static Future<Map<String, dynamic>> analyzeResume({
    required File resumePdf,
    required File jobDescPdf,
  }) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) throw Exception('API key not configured');

    int attempt = 0;
    Duration delay = _initialDelay;
    Exception? lastError;

    while (attempt < _maxRetries) {
      try {
        final result = await _performAnalysis(
          apiKey: apiKey,
          resumePdf: resumePdf,
          jobDescPdf: jobDescPdf,
        );
        return result;
      } catch (e) {
        lastError = e as Exception;
        attempt++;
        if (attempt >= _maxRetries) break;
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
    throw lastError ?? Exception('Analysis failed after $_maxRetries attempts');
  }

  static Future<Map<String, dynamic>> _performAnalysis({
    required String apiKey,
    required File resumePdf,
    required File jobDescPdf,
  }) async {
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    const prompt = '''
You are an ATS (Applicant Tracking System) analyzer. Strictly follow these rules:

1. Respond ONLY with valid JSON in this exact format:
{
  "score": 0-100,
  "strengths": ["list", "of", "matches"],
  "improvements": ["specific", "suggestions"],
  "summary": "brief analysis"
}

2. No additional text/comments
3. No markdown formatting (no ```json```)
4. Keys must be double-quoted
5. Validate your JSON before responding

Now analyze this resume against the job description:
''';

    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart('application/pdf', await jobDescPdf.readAsBytes()),
        DataPart('application/pdf', await resumePdf.readAsBytes()),
      ])
    ];

    final response = await model.generateContent(content);
    final responseText = response.text?.trim() ?? '{}';

    return _parseResponse(responseText);
  }

  static Map<String, dynamic> _parseResponse(String responseText) {
    try {
      // First try direct parsing
      final json = jsonDecode(responseText) as Map<String, dynamic>;
      _validateResponse(json);
      return json;
    } catch (e) {
      // Fallback to cleaned parsing
      final cleaned = _cleanResponse(responseText);
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      _validateResponse(json);
      return json;
    }
  }

  static String _cleanResponse(String dirty) {
    return dirty
        .replaceAll(RegExp(r'^```(json)?|```$'), '') // Remove markdown
        .replaceAll(RegExp(r'//.*?$', multiLine: true), '') // Remove comments
        .replaceAll(RegExp(r',\s*([}\]])'), r'$1') // Fix trailing commas
        .trim();
  }

  static void _validateResponse(Map<String, dynamic> json) {
    final requiredKeys = {'score', 'strengths', 'improvements', 'summary'};
    if (!requiredKeys.every(json.containsKey)) {
      throw FormatException('Missing required keys in response');
    }

    if (json['score'] is! int || json['score'] < 0 || json['score'] > 100) {
      throw FormatException('Invalid score value');
    }
  }
}
class ApiRateLimiter {
  static DateTime? _lastCall;
  static const Duration _minInterval = Duration(seconds: 5);

  static Future<void> waitIfNeeded() async {
    if (_lastCall != null) {
      final elapsed = DateTime.now().difference(_lastCall!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastCall = DateTime.now();
  }
}