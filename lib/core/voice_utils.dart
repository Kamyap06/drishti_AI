
enum VoiceIntent {
  next,
  back,
  retry,
  confirm,
  login,
  register,
  repeat,

  languageEnglish,
  languageHindi,
  languageMarathi,
  unknown
}

class VoiceUtils {
  static VoiceIntent getIntent(String text) {
    String t = text.toLowerCase().trim();
    
    // Back / Cancel
    if (t.contains("back") || t.contains("piche") || t.contains("wapas") || t.contains("maghe") || t.contains("parat") || t.contains("cancel")) {
      return VoiceIntent.back;
    }

    // Next / Confirm / Yes
    if (t.contains("next") || t.contains("yes") || t.contains("confirm") || 
        t.contains("haan") || t.contains("ho") || t.contains("thik") || t.contains("aage") ||
        t.contains("नेक्ट") || t.contains("नेक्स्ट")) {
      return VoiceIntent.next;
    }

    // Retry / No / Change
    if (t.contains("retry") || t.contains("change") || t.contains("no") || 
        t.contains("nahi") || t.contains("nako") || t.contains("badal")) {
      return VoiceIntent.retry;
    }

    // Login
    if (t.contains("login") || t.contains("sign in") || t.contains("pravesh")) {
      return VoiceIntent.login;
    }

    // Register
    if (t.contains("register") || t.contains("create") || t.contains("submit") || 
        t.contains("khata") || t.contains("banva") || t.contains("nondani")) {
      return VoiceIntent.register;
    }

    // Repeat
    if (t.contains("repeat") || t.contains("again") || t.contains("fir se") || t.contains("punha")) {
      return VoiceIntent.repeat;
    }

    /// ================= LANGUAGE SELECTION INTENTS =================
    // Normalize string to handle common STT misinterpretations
    String n = t.replaceAll(" ", "").replaceAll(".", "");
    
    // English
    if (n.contains("english") || n.contains("englis") || n.contains("angrezi") || n.contains("angreji")) {
      return VoiceIntent.languageEnglish;
    }
    
    // Hindi
    if (n.contains("hindi") || n.contains("hindee") || n.contains("indi") || n.contains("हिंदी") || n.contains("हिन्दी")) {
      return VoiceIntent.languageHindi;
    }
    
    // Marathi
    if (n.contains("marathi") || n.contains("marati") || n.contains("marathi") || n.contains("मराठी")) {
      return VoiceIntent.languageMarathi;
    }

    return VoiceIntent.unknown;
  }

  static String normalizeToEnglish(String input) {
    String p = input.trim();
    
    // Remove invisible unicode characters (ZWJ, ZWSP, LTR, RTL, etc.)
    p = p.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F]'), '');
    
    // Convert Devanagari numerals to ASCII
    const devanagariDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    for (int i = 0; i < devanagariDigits.length; i++) {
      p = p.replaceAll(devanagariDigits[i], i.toString());
    }

    p = p.toLowerCase();

    // Convert basic spoken numbers in Hindi/Marathi/English to digits
    final wordMap = {
      'shunya': '0', 'sunya': '0', 'zero': '0',
      'ek': '1', 'one': '1',
      'don': '2', 'do': '2', 'two': '2',
      'teen': '3', 'tin': '3', 'three': '3',
      'char': '4', 'chaar': '4', 'four': '4',
      'paach': '5', 'pach': '5', 'panch': '5', 'five': '5',
      'saha': '6', 'chhah': '6', 'che': '6', 'six': '6',
      'saat': '7', 'sat': '7', 'seven': '7',
      'aath': '8', 'aat': '8', 'eight': '8',
      'nau': '9', 'nav': '9', 'nine': '9',
    };
    
    wordMap.forEach((word, digit) {
      p = p.replaceAll(RegExp(r'\b' + word + r'\b'), digit);
    });

    // Transliterate common Devanagari characters
    final transliterationMap = {
      'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u', 'ऊ': 'oo', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',
      'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ट': 't', 'ठ': 'th',
      'ड': 'd', 'ढ': 'dh', 'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n', 'प': 'p', 'फ': 'f', 'ब': 'b',
      'भ': 'bh', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh', 'ष': 'sh', 'स': 's', 'ह': 'h',
      'ं': 'n', '्': '', 'ा': 'a', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au'
    };
    transliterationMap.forEach((hind, eng) {
      p = p.replaceAll(hind, eng);
    });

    // Whitelist filter (keep only english-safe credentials)
    p = p.replaceAll(RegExp(r'[^a-z0-9@._-]'), '');

    return p;
  }
}
