import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'features/home/home_controller.dart';
import 'features/scam_call/scam_call_session_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeController()),
        ChangeNotifierProvider(create: (_) => ScamCallSessionManager()),
      ],
      child: const CheckVarApp(),
    ),
  );
}
