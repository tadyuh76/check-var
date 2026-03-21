import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_shell.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/home_state_provider.dart';
import 'controllers/news_check_controller.dart';
import 'controllers/scam_call_controller.dart';
import 'services/history_service.dart';
import 'services/notification_service.dart';
import 'screens/history_detail_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Hive.initFlutter();
  await HistoryService.instance.init();
  await NotificationService.init(
    onNotificationTap: _handleNotificationTap,
  );
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('vi'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('vi'),
      startLocale: const Locale('vi'),
      useOnlyLangCode: true,
      child: const CheckVarApp(),
    ),
  );
}

void _handleNotificationTap(String? payload) {
  if (payload == null) return;
  final id = int.tryParse(payload);
  if (id == null) return;
  final entry = HistoryService.instance.getById(id);
  if (entry == null) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => HistoryDetailScreen(entry: entry),
    ),
  );
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
            navigatorKey: navigatorKey,
            title: 'CheckVar',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
