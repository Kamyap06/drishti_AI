
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
        t.contains("haan") || t.contains("ho") || t.contains("thik") || t.contains("aage")) {
      return VoiceIntent.confirm;
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
}
