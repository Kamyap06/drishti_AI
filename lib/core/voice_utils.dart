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
  unknown,
}

class VoiceUtils {
  static VoiceIntent getIntent(String text) {
    String t = text.toLowerCase().trim();

    // Back / Cancel
    if (t.contains("back") ||
        t.contains("piche") ||
        t.contains("pishe") ||
        t.contains("wapas") ||
        t.contains("vapasi") ||
        t.contains("maghe") ||
        t.contains("parat") ||
        t.contains("cancel") ||
        t.contains("radd")) {
      return VoiceIntent.back;
    }

    // Next / Confirm / Yes / Proceed
    if (t.contains("next") ||
        t.contains("yes") ||
        t.contains("confirm") ||
        t.contains("haan") ||
        t.contains("thik") ||
        t.contains("sahi") ||
        t.contains("aage") ||
        t.contains("ho") ||
        t.contains("pudhe") ||
        t.contains("chala") ||
        t.contains("नेक्स्ट") ||
        t.contains("नेक्ट")) {
      return VoiceIntent.next;
    }

    // Retry / No / Change / Try Again
    if (t.contains("retry") ||
        t.contains("change") ||
        t.contains("no") ||
        t.contains("nahi") ||
        t.contains("nako") ||
        t.contains("badal") ||
        t.contains("dobara") ||
        t.contains("phir se") ||
        t.contains("punha") ||
        t.contains("try again")) {
      return VoiceIntent.retry;
    }

    // Login
    if (t.contains("login") ||
        t.contains("sign in") ||
        t.contains("pravesh") ||
        t.contains("shuru")) {
      return VoiceIntent.login;
    }

    // Register / Create Account
    if (t.contains("register") ||
        t.contains("create") ||
        t.contains("submit") ||
        t.contains("khata") ||
        t.contains("banva") ||
        t.contains("nondani") ||
        t.contains("nondni")) {
      return VoiceIntent.register;
    }

    // Repeat
    if (t.contains("repeat") ||
        t.contains("again") ||
        t.contains("fir se") ||
        t.contains("bola") ||
        t.contains("sanga")) {
      return VoiceIntent.repeat;
    }

    /// ================= LANGUAGE SELECTION INTENTS =================
    // Normalize string to handle common STT misinterpretations
    String n = t.replaceAll(" ", "").replaceAll(".", "");

    // English
    if (n.contains("english") ||
        n.contains("angrezi") ||
        n.contains("angreji") ||
        n.contains("ingraji")) {
      return VoiceIntent.languageEnglish;
    }

    // Hindi
    if (n.contains("hindi") ||
        n.contains("hindee") ||
        n.contains("हिंदी") ||
        n.contains("हिन्दी")) {
      return VoiceIntent.languageHindi;
    }

    // Marathi
    if (n.contains("marathi") ||
        n.contains("marati") ||
        n.contains("मराठी")) {
      return VoiceIntent.languageMarathi;
    }

    return VoiceIntent.unknown;
  }

  static String normalizeToEnglish(String input) {
    if (input.isEmpty) return "";

    String p = input.trim();

    // 1. Remove invisible unicode characters
    p = p.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F]'), '');

    // 2. Convert Devanagari numerals to ASCII
    const devanagariDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    for (int i = 0; i < devanagariDigits.length; i++) {
      p = p.replaceAll(devanagariDigits[i], i.toString());
    }

    // 3. Transliteration with schwa handling
    final consonants = {
      'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'n',
      'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'n',
      'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
      'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
      'प': 'p', 'फ': 'f', 'ब': 'b', 'भ': 'bh', 'म': 'm',
      'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh', 
      'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l'
    };

    final vowels = {
      'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u', 'ऊ': 'oo', 
      'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au', 'ऋ': 'ri'
    };

    final vowelMarks = {
      'ा': 'a', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo', 
      'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ृ': 'ri', 'ं': 'n'
    };

    const virama = '्';
    const suppressedMarks = 'ािीुूेैोौृ्';

    String result = "";
    for (int i = 0; i < p.length; i++) {
      String char = p[i];

      if (vowels.containsKey(char)) {
        result += vowels[char]!;
      } else if (consonants.containsKey(char)) {
        result += consonants[char]!;
        
        bool shouldSuppress = false;
        if (i + 1 < p.length) {
          String nextChar = p[i + 1];
          if (suppressedMarks.contains(nextChar)) {
            shouldSuppress = true;
          }
        }
        
        if (!shouldSuppress) {
          if (i + 1 < p.length && p[i+1] != ' ') {
            result += 'a';
          }
        }
      } else if (vowelMarks.containsKey(char)) {
        result += vowelMarks[char]!;
      } else if (char == virama) {
        // Virama joins consonants, skip
      } else {
        result += char;
      }
    }

    p = result.toLowerCase();

    // 4. Whitelist filter: Keep ONLY strictly English small letters [a-z]
    p = p.replaceAll(RegExp(r'[^a-z]'), '');

    return p;
  }
}
