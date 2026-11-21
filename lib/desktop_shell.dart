import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// A native desktop scaffold. Unlike the mobile experience, this fills the
/// application window and does not frame a phone UI against a wallpaper.
class NyxiDesktopShell extends StatelessWidget {
  const NyxiDesktopShell({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onOpenSettings,
    required this.onScan,
    required this.title,
    required this.child,
  });

  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onScan;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      background: const ColoredBox(color: Color(0xFFF8F7FB)),
      enableBackgroundSampling: true,
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.transparent,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 780;
              return Row(
                children: [
                  _DesktopSidebar(
                    compact: compact,
                    selectedTab: selectedTab,
                    onTabSelected: onTabSelected,
                    onOpenSettings: onOpenSettings,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _DesktopTopBar(
                          title: title,
                          compact: compact,
                          onScan: onScan,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              compact ? 20 : 36,
                              26,
                              compact ? 20 : 36,
                              48,
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1320),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.compact,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onOpenSettings,
  });

  final bool compact;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 78 : 222,
      color: const Color(0xFF211726),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 18 : 24, 26, 14, 37),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEB008E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'n',
                    style: TextStyle(
                      fontSize: 27,
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'nyxi',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compact)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 12, 13),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'YOUR SPACE',
                  style: TextStyle(
                    color: Color(0xFF95879C),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          _DesktopNavItem(
            compact: compact,
            label: 'Home',
            icon: CupertinoIcons.house_fill,
            selected: selectedTab == 0,
            onTap: () => onTabSelected(0),
          ),
          _DesktopNavItem(
            compact: compact,
            label: 'Cards',
            icon: CupertinoIcons.creditcard,
            selected: selectedTab == 1,
            onTap: () => onTabSelected(1),
          ),
          _DesktopNavItem(
            compact: compact,
            label: 'Activity',
            icon: CupertinoIcons.chart_bar_fill,
            selected: selectedTab == 2,
            onTap: () => onTabSelected(2),
          ),
          _DesktopNavItem(
            compact: compact,
            label: 'Savings',
            icon: CupertinoIcons.heart_fill,
            selected: selectedTab == 3,
            onTap: () => onTabSelected(3),
          ),
          const Spacer(),
          _DesktopNavItem(
            compact: compact,
            label: 'Settings',
            icon: CupertinoIcons.gear_solid,
            selected: false,
            onTap: onOpenSettings,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 20,
              16,
              compact ? 18 : 20,
              22,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF55334F),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'N',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nyxi preview',
                          style: TextStyle(
                            color: CupertinoColors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Demo account',
                          style: TextStyle(
                            color: Color(0xFFB19EB3),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.compact,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final bool compact;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: compact ? label : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.fromLTRB(compact ? 13 : 12, 3, compact ? 13 : 12, 3),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 15,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF56304D) : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? const Color(0xFFFF8BCB) : const Color(0xFFB6A8BA),
              ),
              if (!compact) ...[
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? CupertinoColors.white
                        : const Color(0xFFC4B7C7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.compact,
    required this.onScan,
  });

  final String title;
  final bool compact;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 77,
      padding: EdgeInsets.symmetric(horizontal: compact ? 22 : 38),
      decoration: const BoxDecoration(
        color: CupertinoColors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF0EDF2)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF211726),
                letterSpacing: -0.5,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDF6),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'DEMO MODE',
              style: TextStyle(
                color: Color(0xFFA92079),
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 15),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onScan,
            child: const Icon(
              CupertinoIcons.qrcode,
              color: Color(0xFF473B4A),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
