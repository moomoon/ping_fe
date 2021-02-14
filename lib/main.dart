import 'package:flutter/material.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/main_router.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
        routeInformationParser: IdentityRoute.identity,
        routerDelegate: MainRouterDelegate());
  }
}
