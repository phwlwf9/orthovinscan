import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_controller.dart';
import 'core/case_repository.dart';
import 'core/export_cache.dart';
import 'features/classification/clinical_knowledge.dart';
import 'features/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<AppController> loading = load();
  Future<AppController> load() async {
    try {
      await ExportCache.clear();
    } catch (_) {
      /* Retry on the next launch. */
    }
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: await CaseRepository.open(),
      knowledge: await ClinicalKnowledge.load(),
      prefs: prefs,
    );
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppController>(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ChangeNotifierProvider.value(
          value: snapshot.data!,
          child: const OrthoApp(),
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Không thể mở kho dữ liệu an toàn.\nKhông có dữ liệu nào bị ghi đè.\nUnable to open secure local storage.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(() => loading = load()),
                            child: const Text('Thử lại / Retry'),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.medical_services_outlined, size: 64),
                          SizedBox(height: 16),
                          Text('OrthoAI'),
                          SizedBox(height: 24),
                          CircularProgressIndicator(),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class OrthoApp extends StatelessWidget {
  const OrthoApp({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff087e8b),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff3f6f8)
          : const Color(0xff0c151c),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
    return MaterialApp(
      title: 'OrthoAI',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: app.themeMode,
      locale: Locale(app.english ? 'en' : 'vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: app.consented ? const AppShell() : const ConsentScreen(),
    );
  }
}
