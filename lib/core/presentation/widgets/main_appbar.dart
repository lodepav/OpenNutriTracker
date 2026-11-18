import 'package:flutter/material.dart';

class MainAppbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData iconData;

  const MainAppbar({super.key, required this.title, required this.iconData});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // [fork] S279 tab-appbar: no decorative icon in Back's slot; the
      // title starts at the keyline as on pushed pages
      // leading: Icon(iconData),
      // [/fork]
      title: Text(title),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
