import 'package:flutter/material.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/main_router.dart';
import 'package:ping_fe/scroll_demo.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            hintStyle: TextStyle(color: Colors.grey[600]),
            fillColor: Color.lerp(Colors.white, Colors.black, 0.7),
            filled: true,
            isDense: true,
            focusColor: Colors.red,
            contentPadding: EdgeInsets.only(top: 16, left: 14),
            border: OutlineInputBorder(borderSide: BorderSide.none)),
      ),
      child:
          // MaterialApp(home: SafeArea(child: PositionDemo()))
          MaterialApp.router(
              routeInformationParser: IdentityRoute.identity,
              routerDelegate: MainRouterDelegate()),
    );
  }
}
