import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_controller.dart';
import 'package:night_reader/shared/navigation/app_route_observer.dart';

class ReaderV2ReadTimeScope extends StatefulWidget {
  const ReaderV2ReadTimeScope({
    super.key,
    required this.book,
    required this.child,
  });

  final Book book;
  final Widget child;

  @override
  State<ReaderV2ReadTimeScope> createState() => _ReaderV2ReadTimeScopeState();
}

class _ReaderV2ReadTimeScopeState extends State<ReaderV2ReadTimeScope>
    with WidgetsBindingObserver, RouteAware {
  late final ReaderV2ReadTimeController _controller;
  ModalRoute<void>? _observedRoute;
  bool _routeVisible = true;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appInForeground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = ReaderV2ReadTimeController(
      bookName: widget.book.name,
      readRecordDao: getIt<ReadRecordDao>(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route != null && !identical(route, _observedRoute)) {
      if (_observedRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _observedRoute = route;
      _routeVisible = route.isCurrent;
      appRouteObserver.subscribe(this, route);
    }
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncTimer();
  }

  @override
  void didPush() {
    _routeVisible = true;
    _syncTimer();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncTimer();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncTimer();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncTimer();
  }

  void _syncTimer() {
    if (_appInForeground && _routeVisible) {
      _controller.start();
    } else {
      unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
