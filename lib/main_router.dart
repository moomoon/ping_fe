import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ping_fe/chat.dart';
import 'package:ping_fe/chat_list.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/sign_in.dart';

class MainRouterDelegate extends RouterDelegate<RouteInformation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<RouteInformation> {
  List<Page> _pages = [];
  static const chatList =
      MaterialPage(key: ValueKey('chat_list'), child: ChatListWidget());
  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const NotFound();
    }
    return StreamBuilder<Account>(
        stream: context.accountStore.stream,
        initialData: context.accountStore.value,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SignIn();
          }
          return Navigator(
            key: navigatorKey,
            pages: [
              if (_pages.isEmpty) chatList else ..._pages,
            ],
            onPopPage: (route, result) {
              if (!route.didPop(result)) {
                return false;
              }
              if (_pages.isNotEmpty) {
                _pages.removeLast();
                notifyListeners();
                return true;
              }
              return false;
            },
          );
        }).inheritingDefaultSlot(this);
  }

  @override
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  pushChat(Chat chat) {}

  popUntilChatList() {
    _pages = [];
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(RouteInformation configuration) {
    final uri = Uri.parse(configuration.location);
    // Handle '/'
    if (uri.pathSegments.length == 0) {
      _pages = [
        const MaterialPage(key: ValueKey('chat_list'), child: ChatListWidget())
      ];
    }

    // // Handle '/book/:id'
    // if (uri.pathSegments.length == 2) {
    //   if (uri.pathSegments[0] != 'book') return BookRoutePath.unknown();
    //   var remaining = uri.pathSegments[1];
    //   var id = int.tryParse(remaining);
    //   if (id == null) return BookRoutePath.unknown();
    //   return BookRoutePath.details(id);
    // }

    // // Handle unknown routes
    // return BookRoutePath.unknown();
  }
}

class NotFound extends StatelessWidget {
  const NotFound() : super();

  @override
  Widget build(BuildContext context) {
    return const Text('not found');
  }
}

extension MainRouter on BuildContext {
  MainRouterDelegate get mainRouter => peekInherited();
}
