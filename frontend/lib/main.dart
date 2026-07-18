import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/ai_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/category_provider.dart';
import 'providers/lesson_provider.dart';
import 'providers/search_provider.dart';
import 'providers/subject_provider.dart';
import 'providers/youtube_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fix ("Black status bar / safe area issue - all screens"): setting
  // ONLY the overlay style (colors) isn't enough on several Android
  // versions/OEM skins - without also telling Android to actually draw
  // edge-to-edge, the OS can still paint its own default system bar
  // background (black) behind/around our "transparent" request instead
  // of truly letting the app's own background show through. Enabling
  // edge-to-edge mode is what makes the transparent status/nav bar
  // colors below actually take effect consistently.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  runApp(const AiTutorApp());
}

class AiTutorApp extends StatelessWidget {
  const AiTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Day 2: Course & Learning Management providers.
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => SubjectProvider()),
        ChangeNotifierProvider(create: (_) => LessonProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => AiProvider()),
        // Lesson videos: YouTube recommended-videos integration.
        ChangeNotifierProvider(create: (_) => YoutubeProvider()),
      ],
      child: const _AppRoot(),
    );
  }
}

/// Hosts the single, long-lived GoRouter instance.
///
/// QA fix ("Router rebuild issue"): this used to be a Consumer<AuthProvider>
/// wrapping MaterialApp.router, building `AppRouter(authProvider).router`
/// fresh inside the builder - so every single authProvider.notifyListeners()
/// call (login, logout, a profile field updating, anything) constructed a
/// brand new GoRouter, discarding the entire navigation stack. GoRouter
/// already has its own mechanism for reacting to auth changes without a
/// rebuild - `refreshListenable: authProvider.statusNotifier` inside
/// AppRouter - so the router itself only needs to be built once, here in
/// initState, and never rebuilt for the lifetime of the app.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(context.read<AuthProvider>()).router;
  }

  @override
  Widget build(BuildContext context) {
    // Fallback status bar style for screens with no AppBar (e.g. the
    // Home/Dashboard screen) - using AnnotatedRegion (not a raw
    // SystemChrome call) so it participates in the same override/restore
    // stack that AppBar's systemOverlayStyle uses, instead of the two
    // mechanisms silently fighting each other during navigation.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: MaterialApp.router(
        title: 'AI Tutor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
      ),
    );
  }
}
