import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ping_fe/chat_detail.dart';
import 'package:ping_fe/chat_list.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/protos/chat.pb.dart';
import 'package:ping_fe/sign_in.dart';

class MainRouterDelegate extends RouterDelegate<RouteInformation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<RouteInformation> {
  List<Page> _pages = [];
  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const NotFound();
    }
    return StreamBuilder<Account>(
        stream: context.accountStore.stream,
        initialData: context.accountStore.value,
        builder: (context, snapshot) {
          return Navigator(
            key: navigatorKey,
            pages: [
              if (!snapshot.hasData)
                const MaterialPage(key: ValueKey('sign_in'), child: SignIn())
              else if (_pages.isEmpty)
                ChatListWidget.page
              else
                ..._pages,
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

  pushChat(Chat chat) {
    _pages.add(MaterialPage(
        key: ValueKey('chat:${chat.id}'),
        child: ChatDetail(
          chatId: chat.id,
        )));
    notifyListeners();
  }

  popUntilChatList() {
    _pages = [];
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(RouteInformation configuration) {
    final uri = Uri.parse(configuration.location);
    // Handle '/'
    if (uri.pathSegments.length == 0) {
      _pages = [ChatListWidget.page];
    }
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
