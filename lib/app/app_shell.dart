import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/kraft_tokens.dart';
import '../widgets/kraft_nav_bar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    void selectBranch(int index) =>
        shell.goBranch(index, initialLocation: index == shell.currentIndex);
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];

    return Shortcuts(
      shortcuts: {
        for (var i = 0; i < 4; i++) ...{
          SingleActivator(digitKeys[i], control: true): _NavigateIntent(i),
          SingleActivator(digitKeys[i], meta: true): _NavigateIntent(i),
        },
      },
      child: Actions(
        actions: {
          _NavigateIntent: CallbackAction<_NavigateIntent>(
            onInvoke: (intent) {
              selectBranch(intent.index);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final desktop =
                    constraints.maxWidth >= kDesktopNavigationBreakpoint;
                if (desktop) {
                  return Row(
                    children: [
                      KraftNavigationRail(
                        currentIndex: shell.currentIndex,
                        onSelect: selectBranch,
                      ),
                      Expanded(child: shell),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: shell),
                    KraftNavBar(
                      currentIndex: shell.currentIndex,
                      onSelect: selectBranch,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigateIntent extends Intent {
  const _NavigateIntent(this.index);

  final int index;
}
