import 'package:flutter/material.dart';

import 'reader_nav_scope.dart';

/// Publishes whether a page covers the mushaf, and the first popup overlay.
class ReaderRouteObserver extends NavigatorObserver {
  ReaderRouteObserver(this.nav);

  final ReaderNavController nav;
  final List<Route<dynamic>> _stack = [];
  NavigatorState? _bound;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _rebindIfNeeded();
    _stack.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _rebindIfNeeded();
    _stack.remove(route);
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _rebindIfNeeded();
    _stack.remove(route);
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _rebindIfNeeded();
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _stack.removeAt(index);
      } else {
        _stack[index] = newRoute;
      }
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _publish();
  }

  void _rebindIfNeeded() {
    if (identical(navigator, _bound)) return;
    _stack.clear();
    _bound = navigator;
  }

  void _publish() {
    final pageAboveHome =
        _stack.length > 1 && _stack.skip(1).any((route) => route is PageRoute);
    nav.publishRouteCover(pageAboveHome: pageAboveHome);
  }
}
