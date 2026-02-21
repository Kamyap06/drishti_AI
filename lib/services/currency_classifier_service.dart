import 'dart:async';

class CurrencyResult {
  final String type; // 'note', 'coin', 'unknown'
  final int value;
  final double confidence;
  final String locale;

  const CurrencyResult({
    required this.type,
    required this.value,
    required this.confidence,
    required this.locale,
  });

  bool get isValid => value > 0;
}

class MultilingualCurrencyPipeline {
  final CurrencyClassifierService _classifier = CurrencyClassifierService();

  Future<CurrencyResult> process(String rawOcrText, String locale) async {
    String normalized = normalize(rawOcrText);
    return await _classifier.classify(normalized, locale);
  }

  String normalize(String text) {
    String t = text.toLowerCase();

    // Normalize RBI variations
    t = t.replaceAll(
      RegExp(
        r'भारतीय रिज़र्व बैंक|भारतीय रिजर्व बैंक|रिज़र्व बैंक ऑफ इंडिया|reserve bank of india|rbi',
      ),
      'rbi_marker',
    );

    // Normalize numerals and symbols
    t = t.replaceAll('₹', ' rs ');
    t = t.replaceAll('रुपये', ' rs ');
    t = t.replaceAll('रुपया', ' rs ');
    t = t.replaceAll('rupees', ' rs ');
    t = t.replaceAll('rupee', ' rs ');

    // Hindi/Marathi numbers mapping to numeric values
    Map<String, String> synonyms = {
      'एक': '1',
      'one': '1',
      'दो': '2',
      'दोन': '2',
      'two': '2',
      'पांच': '5',
      'पाच': '5',
      'five': '5',
      'दस': '10',
      'दहा': '10',
      'ten': '10',
      'बीस': '20',
      'वीस': '20',
      'twenty': '20',
      'पचास': '50',
      'पन्नास': '50',
      'fifty': '50',
      'सौ': '100',
      'शंभर': '100',
      'hundred': '100',
      'एक सौ': '100',
      'one hundred': '100',
      'दो सौ': '200',
      'दोनशे': '200',
      'two hundred': '200',
      'पांच सौ': '500',
      'पाचशे': '500',
      'five hundred': '500',
      'दो हजार': '2000',
      'दोन हजार': '2000',
      'two thousand': '2000',
    };

    synonyms.forEach((key, value) {
      t = t.replaceAll(RegExp(r'\b' + key + r'\b'), value);
    });

    // Remove extra whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

    return t;
  }
}

class CurrencyClassifierService {
  /// Analyzes the normalized text and returns structured data
  /// Fallback to visual AI model can be plugged in here if OCR confidence is low
  Future<CurrencyResult> classify(String normalizedText, String locale) async {
    int detectedValue = 0;
    String type = 'unknown';
    double confidence = 0.0;

    bool hasRbi = normalizedText.contains('rbi_marker');
    bool hasRs = normalizedText.contains('rs');

    final valueList = [2000, 500, 200, 100, 50, 20, 10, 5, 2, 1];

    for (int v in valueList) {
      if (RegExp(r'\b$v\b').hasMatch(normalizedText)) {
        detectedValue = v;
        break;
      }
    }

    if (detectedValue > 0) {
      /// --- NOTE vs COIN smarter rule ---
      if (hasRbi || detectedValue >= 20) {
        type = 'note';
      } else {
        type = 'coin';
      }

      confidence = hasRbi ? 0.95 : 0.75;
    } else if (hasRbi || hasRs) {
      type = 'note';
      confidence = 0.5;
    }

    return CurrencyResult(
      type: type,
      value: detectedValue,
      confidence: confidence,
      locale: locale,
    );
  }
}

class CurrencySpeechFormatter {
  static String formatGreeting(String locale) {
    if (locale == 'hi') return "तैयार हूँ, स्कैन करें।";
    if (locale == 'mr') return "तयार आहे, स्कॅन करा।";
    return "Ready. Say detect or scan.";
  }

  static String formatScanning(String locale) {
    if (locale == 'hi') return "स्कैन कर रहा हूँ...";
    if (locale == 'mr') return "स्कॅन करत आहे...";
    return "Scanning...";
  }

  static String formatError(String locale) {
    if (locale == 'hi') return "माफ़ करना, स्कैन नहीं हो पाया।";
    if (locale == 'mr') return "माफ़ करा, स्कॅन होऊ शकले नाही।";
    return "Sorry, couldn't scan properly.";
  }

  static String formatResult(CurrencyResult result) {
    if (!result.isValid) {
      if (result.type == 'note' && result.confidence == 0.5) {
        if (result.locale == 'hi')
          return "पैसा दिख रहा है, पर कितने का है समझ नहीं आया।";
        if (result.locale == 'mr')
          return "पैसे दिसत आहेत, पण किती रुपयाचे आहे ते कळलं नाही।";
        return "I see money, but can't read the value.";
      }
      if (result.locale == 'hi') return "मुझे कोई पैसा नहीं दिखा।";
      if (result.locale == 'mr') return "मला कोणतेही पैसे दिसले नाहीत।";
      return "I didn't detect any currency.";
    }

    Map<int, String> hiNums = {
      2000: 'दो हजार',
      500: 'पांच सौ',
      200: 'दो सौ',
      100: 'एक सौ',
      50: 'पचास',
      20: 'बीस',
      10: 'दस',
      5: 'पांच',
      2: 'दो',
      1: 'एक',
    };
    Map<int, String> mrNums = {
      2000: 'दोन हजार',
      500: 'पाचशे',
      200: 'दोनशे',
      100: 'शंभर',
      50: 'पन्नास',
      20: 'वीस',
      10: 'दहा',
      5: 'पाच',
      2: 'दोन',
      1: 'एक',
    };

    if (result.locale == 'hi') {
      String typeHi = result.type == 'note' ? 'का नोट' : 'का सिक्का';
      return "यह ${hiNums[result.value] ?? result.value} रुपये $typeHi है।";
    } else if (result.locale == 'mr') {
      String typeMr = result.type == 'note' ? 'ची नोट' : 'चे नाणे';
      return "ही ${mrNums[result.value] ?? result.value} रुपया$typeMr आहे।";
    }

    String typeEn = result.type == 'note' ? 'note' : 'coin';
    return "This is a ${result.value} rupee $typeEn.";
  }
}
