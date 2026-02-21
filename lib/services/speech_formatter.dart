class SpeechFormatter {
  static String formatGreeting(String locale) {
    if (locale == 'hi') return "टेक्स्ट पढ़ने के लिए 'स्कैन' बोलें।";
    if (locale == 'mr') return "मजकूर वाचण्यासाठी 'स्कॅन' म्हणा.";
    return "Image to Speech. Say 'Detect' to read text.";
  }

  static String formatScanning(String locale) {
    if (locale == 'hi') return "पढ़ रहे हैं...";
    if (locale == 'mr') return "वाचत आहे...";
    return "Reading...";
  }

  static String formatNoText(String locale) {
    if (locale == 'hi') return "कोई टेक्स्ट नहीं मिला।";
    if (locale == 'mr') return "कोणताच मजकूर आढळला नाही.";
    return "No text found.";
  }

  static String formatError(String locale) {
    if (locale == 'hi') return "प्रोसेस करने में त्रुटि।";
    if (locale == 'mr') return "प्रक्रिया करण्यात त्रुटी.";
    return "Error processing.";
  }

  static String formatTranslationPrompt(List<String> options, String locale) {
    String mapLanguage(String opt, String loc) {
      if (opt == 'en') {
        if (loc == 'hi') return "अंग्रेज़ी";
        if (loc == 'mr') return "इंग्रजी";
        return "English";
      }
      if (opt == 'hi') {
        if (loc == 'hi') return "हिंदी";
        if (loc == 'mr') return "हिंदी";
        return "Hindi";
      }
      if (opt == 'mr') {
        if (loc == 'hi') return "मराठी";
        if (loc == 'mr') return "मराठी";
        return "Marathi";
      }
      return opt;
    }

    String prompt = "";
    if (options.isEmpty) return prompt;

    if (locale == 'hi') {
      prompt =
          "क्या आप इसका अनुवाद ${options.map((e) => mapLanguage(e, locale)).join(" या ")} में चाहते हैं?";
    } else if (locale == 'mr') {
      prompt =
          "तुम्हाला याचं भाषांतर ${options.map((e) => mapLanguage(e, locale)).join(" किंवा ")} मध्ये हवं आहे का?";
    } else {
      prompt =
          "Do you want to translate this text into ${options.map((e) => mapLanguage(e, locale)).join(" or ")}?";
    }
    return prompt;
  }
}
