import 'package:flutter/widgets.dart';

import '../services/entitlement_service.dart';

/// Exposes the verified single ai_access entitlement to licensing settings.
/// It is not a generic Feature authorizer and cannot grant business rights.
class EntitlementServiceScope extends InheritedWidget {
  const EntitlementServiceScope({
    required this.entitlementService,
    required super.child,
    super.key,
  });

  final EntitlementService entitlementService;

  static EntitlementService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EntitlementServiceScope>()
          ?.entitlementService;

  @override
  bool updateShouldNotify(EntitlementServiceScope oldWidget) =>
      !identical(entitlementService, oldWidget.entitlementService);
}
