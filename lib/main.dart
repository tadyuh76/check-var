import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app_shell.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/home_state_provider.dart';
import 'controllers/news_check_controller.dart';
import 'controllers/scam_call_controller.dart';
import 'services/history_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await HistoryService.instance.init();
  await NotificationService.init();
  runApp(const CheckVarApp());
}

class CheckVarApp extends StatelessWidget {
  const CheckVarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => HomeStateProvider()),
        ChangeNotifierProvider.value(value: NewsCheckController.instance),
        ChangeNotifierProvider(create: (_) => ScamCallController()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'CheckVar',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
