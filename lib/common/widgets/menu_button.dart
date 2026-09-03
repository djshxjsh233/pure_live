import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/menu_list_tile.dart';

/// AppBar 菜单按钮：设置 / 关于 / 观看历史（登录入口已随 Firebase 移除）
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  final menuRoutes = const [RoutePath.kSettings, RoutePath.kAbout, RoutePath.kHistory];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      tooltip: i18n('menu'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(12, 0),
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.menu_rounded),
      onSelected: (int index) {
        Get.toNamed(menuRoutes[index]);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: const Icon(Remix.settings_5_line), text: i18n("settings_title")),
        ),
        PopupMenuItem(
          value: 1,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: const Icon(Remix.information_line), text: i18n("about")),
        ),
        PopupMenuItem(
          value: 2,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: const Icon(Remix.history_line), text: i18n("history")),
        ),
      ],
    );
  }
}