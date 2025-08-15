import 'dart:ui';

class AuroraMessageService {
  /// Returns a descriptive message based on Kp index
  static String getKpMessage(double kp) {
    final kpInt = kp.round();

    if (kpInt == 0) return "Aurora might form low to the north if Bz goes negative";
    if (kpInt == 1) return "Aurora might form Low to the northern horizon";
    if (kpInt == 2) return "Aurora might form to the north";
    if (kpInt == 3) return "Aurora will form to the north if Bz is negative";
    if (kpInt == 4 || kpInt == 5) return "Aurora will form to the North and Overhead";
    if (kpInt >= 6 && kpInt <= 9) return "✨ Aurora can form anywhere - Let's dance to the disco lights!";

    return "Kp index not available";
  }

  /// Returns a descriptive message based on BzH value
  static String getBzHMessage(double bzH) {
    if (bzH > 6) return "✨ Strong aurora conditions – Get out now!";
    if (bzH > 4.5) return "Strong aurora likely now and in the next few hours";
    if (bzH > 3) return "Moderate aurora likely now and in the next few hours";
    if (bzH > 1.5) return "Faint aurora likely now and in the next few hours";
    if (bzH > 0) return "Weak aurora possible now and in the next hours";
    return "Aurora unlikely now and in the next 2 hours";
  }

  /// Returns a combined status message considering both Kp and BzH
  static String getCombinedAuroraMessage(double kp, double bzH) {
    final kpInt = kp.round();

    // For exceptional conditions - combine location and intensity
    if (bzH > 6 && kpInt >= 6) {
      return "✨ EXCEPTIONAL! Strong aurora conditions anywhere in the sky - Get out now!";
    }
    if (bzH > 6 && kpInt >= 4) {
      return "✨ EXCEPTIONAL! Strong aurora conditions overhead and to the north - Get out now!";
    }
    if (bzH > 6) {
      return "✨ Strong aurora conditions active! Check northern horizon and overhead.";
    }
    if (kpInt >= 6) {
      return "✨ Aurora can form anywhere in the sky - Let's dance to the disco lights!";
    }

    // Strong intensity with location context
    if (bzH > 4.5 && kpInt >= 4) {
      return "⚡ Strong aurora likely overhead and to the north now and in the next few hours";
    }
    if (bzH > 4.5 && kpInt >= 3) {
      return "⚡ Strong aurora likely to the north now and in the next few hours";
    }
    if (bzH > 4.5) {
      return "⚡ Strong aurora likely now - watch northern horizon and overhead areas";
    }

    // Moderate intensity with location
    if (bzH > 3 && kpInt >= 4) {
      return "🌌 Moderate aurora likely overhead and to the north now and in the next few hours";
    }
    if (bzH > 3 && kpInt >= 3) {
      return "🌌 Moderate aurora likely to the north now and in the next few hours";
    }
    if (bzH > 3) {
      return "🌌 Moderate aurora likely to the northern horizon now and in the next few hours";
    }

    // Faint intensity with location
    if (bzH > 1.5 && kpInt >= 4) {
      return "✨ Faint aurora possible overhead and to the north in the next few hours";
    }
    if (bzH > 1.5 && kpInt >= 3) {
      return "✨ Faint aurora possible to the north in the next few hours";
    }
    if (bzH > 1.5) {
      return "✨ Faint aurora possible low to the northern horizon in the next few hours";
    }

    // Weak conditions - rely more on Kp location guidance
    if (kpInt >= 4) {
      return "🌌 Aurora will form overhead and to the north if Bz turns negative";
    }
    if (kpInt >= 3) {
      return "🧭 Aurora will form to the north if Bz goes negative";
    }
    if (kpInt >= 2) {
      return "🔍 Aurora might form to the northern horizon";
    }
    if (kpInt >= 1) {
      return "👀 Aurora might form low to the northern horizon";
    }

    // Very quiet conditions
    if (bzH > 0) {
      return "💤 Weak aurora possible in northern areas, but conditions are marginal";
    }

    return "😴 Aurora unlikely in the next 2 hours - too quiet for northern latitudes";
  }

  /// Returns an appropriate color for the aurora status
  static Color getStatusColor(double kp, double bzH) {
    final kpInt = kp.round();

    // Strong conditions - bright colors
    if (bzH > 6 || kpInt >= 6) return const Color(0xFFFFD700); // Gold
    if (bzH > 4.5 || kpInt >= 4) return const Color(0xFFFF6B35); // Orange-red

    // Moderate conditions
    if (bzH > 3 || kpInt >= 3) return const Color(0xFF4ECDC4); // Teal

    // Weak conditions
    if (bzH > 1.5 || kpInt >= 2) return const Color(0xFF45B7D1); // Light blue
    if (bzH > 0 || kpInt >= 1) return const Color(0xFF96CEB4); // Light green

    // No aurora
    return const Color(0xFF95A5A6); // Gray
  }

  /// Returns aurora activity level as a string
  static String getActivityLevel(double kp, double bzH) {
    final kpInt = kp.round();

    if (bzH > 6 || kpInt >= 6) return "EXCEPTIONAL";
    if (bzH > 4.5 || kpInt >= 4) return "STRONG";
    if (bzH > 3 || kpInt >= 3) return "MODERATE";
    if (bzH > 1.5 || kpInt >= 2) return "WEAK";
    if (bzH > 0 || kpInt >= 1) return "MINIMAL";
    return "NONE";
  }

  /// Returns specific advice for aurora hunters
  static String getAuroraAdvice(double kp, double bzH) {
    final kpInt = kp.round();

    // Exceptional conditions - location + intensity
    if (bzH > 6 && kpInt >= 6) {
      return "🚗 DROP EVERYTHING! Strong aurora active anywhere in the sky right now!";
    }
    if (bzH > 6 && kpInt >= 4) {
      return "🚗 GET OUT NOW! Strong aurora active overhead and to the north!";
    }
    if (bzH > 6) {
      return "🚗 Strong aurora conditions active! Head north and look overhead too!";
    }

    // Strong intensity with location guidance
    if (bzH > 4.5 && kpInt >= 4) {
      return "📸 Get ready! Strong aurora likely overhead and northern horizon in next few hours.";
    }
    if (bzH > 4.5 && kpInt >= 3) {
      return "📸 Head to dark northern areas! Strong aurora likely to the north soon.";
    }
    if (bzH > 4.5) {
      return "📸 Find northern viewpoint! Strong aurora likely on northern horizon.";
    }

    // Moderate intensity with location
    if (bzH > 3 && kpInt >= 4) {
      return "👀 Good conditions! Moderate aurora likely overhead and to the north.";
    }
    if (bzH > 3 && kpInt >= 3) {
      return "👀 Watch northern sky! Moderate aurora likely to the north.";
    }
    if (bzH > 3) {
      return "👀 Face north! Moderate aurora likely on northern horizon.";
    }

    // Faint conditions with location
    if (bzH > 1.5 && kpInt >= 4) {
      return "⏰ Stay alert! Faint aurora possible overhead and northern areas.";
    }
    if (bzH > 1.5 && kpInt >= 3) {
      return "⏰ Watch northern horizon! Faint aurora possible to the north.";
    }
    if (bzH > 1.5) {
      return "⏰ Check low northern horizon! Faint aurora possible in next few hours.";
    }

    // Kp-based location guidance when BzH is low
    if (kpInt >= 4) {
      return "🌌 Good Kp! Aurora will form overhead and north if Bz turns negative.";
    }
    if (kpInt >= 3) {
      return "🧭 Watch for negative Bz! Aurora will form to the north.";
    }
    if (kpInt >= 2) {
      return "🔍 Face north and wait! Aurora might form on northern horizon.";
    }
    if (kpInt >= 1) {
      return "👁️ Very low activity. Aurora might form low to the northern horizon.";
    }

    // Very quiet
    if (bzH > 0) {
      return "💤 Marginal conditions. Only faint activity possible in far northern areas.";
    }

    return "😴 Too quiet for aurora at northern latitudes. Perfect time to plan for better conditions!";
  }
} 