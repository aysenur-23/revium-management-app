/**
 * Responsive design yardımcı sınıfı
 * Farklı ekran boyutlarına göre dinamik değerler sağlar
 */

import 'package:flutter/material.dart';

class ResponsiveHelper {
  /// Ekran genişliğine göre padding değeri döndürür
  static double getPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) {
      return 12.0; // Çok küçük ekranlar
    } else if (width < 600) {
      return 16.0; // Küçük ekranlar (telefon)
    } else if (width < 900) {
      return 24.0; // Orta ekranlar (tablet)
    } else {
      return 32.0; // Büyük ekranlar (desktop)
    }
  }

  /// Ekran genişliğine göre spacing değeri döndürür
  static double getSpacing(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) {
      return 8.0;
    } else if (width < 600) {
      return 12.0;
    } else {
      return 16.0;
    }
  }

  /// Ekran genişliğine göre logo boyutu döndürür
  static double getLogoSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) {
      return 80.0;
    } else if (width < 600) {
      return 120.0;
    } else {
      return 150.0;
    }
  }

  /// Ekran genişliğine göre font scale döndürür
  static double getFontScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) {
      return 0.9;
    } else if (width < 600) {
      return 1.0;
    } else {
      return 1.1;
    }
  }

  /// Küçük ekran kontrolü
  static bool isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  /// Orta ekran kontrolü
  static bool isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 900;
  }

  /// Büyük ekran kontrolü
  static bool isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 900;
  }

  /// TabBar için sadece icon gösterilip gösterilmeyeceğini döndürür
  static bool showTabLabels(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600;
  }
}

