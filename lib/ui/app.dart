import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

class TrDailyApp extends StatelessWidget {
  const TrDailyApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
        title: 'Tr-Daily',
        debugShowCheckedModeBanner: false,
        theme: TrTheme.dark(),
        home: HomeShell(state: state),
      ),
    );
  }
}
