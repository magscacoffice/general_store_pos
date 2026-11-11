import 'dart:io';

import 'package:flutter/material.dart';

import 'pos_windows.dart';

Widget? desktopWorkspaceButton() {
  if (!Platform.isWindows) return null;
  return Builder(
    builder: (context) => IconButton(
      tooltip: 'Open Dashboard window',
      icon: const Icon(Icons.dashboard_outlined),
      onPressed: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        } else {
          PosWindows.openDashboard();
        }
      },
    ),
  );
}

Widget? desktopReturnButton() {
  if (!Platform.isWindows) return null;
  return Builder(
    builder: (context) => TextButton.icon(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.reply),
      label: const Text('Return'),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
    ),
  );
}
