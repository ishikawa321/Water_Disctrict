import 'dart:async';

import 'package:flutter/widgets.dart';

/// Polling also works when Supabase Realtime isn't enabled for financial tables.
mixin BillingRefresh<T extends StatefulWidget> on State<T> {
  Timer? _billingTimer;
  bool _billingForeground = true;
  late final _billingObserver = _BillingLifecycle((state) {
    _billingForeground = state == AppLifecycleState.resumed;
    if (_billingForeground && mounted) unawaited(refreshRemoteBilling());
  });
  Future<void> refreshRemoteBilling();

  void startBillingRefresh() {
    WidgetsBinding.instance.addObserver(_billingObserver);
    _billingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          _billingForeground &&
          ModalRoute.of(context)?.isCurrent != false) {
        unawaited(refreshRemoteBilling());
      }
    });
  }

  void stopBillingRefresh() {
    _billingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_billingObserver);
  }
}

class _BillingLifecycle extends WidgetsBindingObserver {
  _BillingLifecycle(this.onChange);
  final void Function(AppLifecycleState) onChange;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}
