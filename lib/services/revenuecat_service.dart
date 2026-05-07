import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class RevenueCatService {
  RevenueCatService._();

  static const String _apiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: 'test_lGjIcigiVuuPcSbcEEuQaNywoak',
  );

  static bool _isConfigured = false;

  static Future<void> initialize() async {
    if (_isConfigured || _apiKey.trim().isEmpty) {
      return;
    }

    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);
    final configuration = PurchasesConfiguration(_apiKey);
    await Purchases.configure(configuration);
    _isConfigured = true;
  }

  static Future<PaywallResult> presentPaywall() async {
    await initialize();
    return RevenueCatUI.presentPaywall();
  }
}
