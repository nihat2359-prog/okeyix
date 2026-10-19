import 'dart:async';
import 'package:flutter/material.dart';

/// A local visual clock. It owns no game/network state and stops when hidden.
class PeriodicUiBuilder extends StatefulWidget {
  final Duration interval;
  final bool enabled;
  final WidgetBuilder builder;
  const PeriodicUiBuilder({
    super.key,
    required this.interval,
    required this.builder,
    this.enabled = true,
  });
  @override
  State<PeriodicUiBuilder> createState() => _PeriodicUiBuilderState();
}

class _PeriodicUiBuilderState extends State<PeriodicUiBuilder>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PeriodicUiBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _timer?.cancel();
      _timer = null;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (_foreground && mounted) setState(() {});
  }

  void _sync() {
    final run = widget.enabled && _foreground && TickerMode.of(context);
    if (!run) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
