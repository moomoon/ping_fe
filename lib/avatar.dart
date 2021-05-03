import 'package:flutter/material.dart';
import 'package:ping_fe/protos/chat.pb.dart';

class Avatar extends StatelessWidget {
  final Profile profile;
  final double radius;
  final bool hero;

  const Avatar(
      {Key key, @required this.profile, this.radius = 18, this.hero = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    String avatar = profile?.avatarUrl;
    Widget content;
    if (avatar?.isNotEmpty != true) {
      var name = profile?.nickname;
      if (name?.isNotEmpty != true) {
        name = profile?.username;
      }
      if (name?.isNotEmpty == true) {
        final initial = _initial(name);
        if (initial.isNotEmpty)
          content = CircleAvatar(
            radius: radius,
            child: Text(
              initial,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: radius * 0.9, color: Colors.white),
            ),
            backgroundColor: initialBackgroundColors[
                initial.codeUnitAt(0) % initialBackgroundColors.length],
          );
      }
      content ??= Icon(
        Icons.account_circle,
        color: Colors.white,
        size: radius * 2,
      );
    } else {
      content = CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatar),
      );
    }

    if (hero == true && profile?.username != null) {
      content = Hero(tag: profile.username, child: content);
    }
    return content;
  }

  static const List<Color> initialBackgroundColors = [
    Color.fromARGB(255, 56, 142, 60),
    Color.fromARGB(255, 174, 57, 20),
    Color.fromARGB(255, 194, 24, 91),
    Color.fromARGB(255, 144, 19, 254),
    Color.fromARGB(255, 168, 129, 30),
  ];
}

String _initial(String name) {
  final sb = StringBuffer();
  name = name.trim();
  for (final s in name.split(RegExp(r'\s+')).take(2))
    if (s.isNotEmpty) sb.writeCharCode(s.codeUnitAt(0));
  if (sb.length < 2 && name.length > 1) sb.writeCharCode(name.codeUnitAt(1));
  return sb.toString().toUpperCase();
}
