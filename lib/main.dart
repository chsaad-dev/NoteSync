import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'core/di/injection_container.dart' as di;
import 'core/theme/app_theme.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/biometric_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/sync_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/app_lock_screen.dart';
import 'presentation/screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (safely catches exceptions if local configurations are missing)
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Load Dotenv Configuration
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  final workerUrl = dotenv.env['CLOUDFLARE_WORKER_URL'] ?? 'https://your-worker-url.workers.dev';
  final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? 'your_cloudinary_cloud_name';

  // Initialize dependencies
  await di.init(
    workerUrl: workerUrl,
    cloudinaryCloudName: cloudName,
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupBackgroundSyncListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  void _setupBackgroundSyncListeners() {
    // 1. Connectivity Regained listener
    _connectivitySubscription = di.sl<Connectivity>().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        _triggerBackgroundSync();
      }
    });

    // 2. Periodic Timer (Every 2 minutes)
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _triggerBackgroundSync();
    });
  }

  void _triggerBackgroundSync() {
    final auth = ref.read(authProvider);
    if (auth is Authenticated) {
      ref.read(syncProvider.notifier).syncNow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final biometric = ref.read(biometricProvider);
      if (biometric.isEnabled) {
        ref.read(biometricProvider.notifier).lock();
      }
    } else if (state == AppLifecycleState.resumed) {
      _triggerBackgroundSync();
      
      final biometric = ref.read(biometricProvider);
      if (biometric.isEnabled && biometric.isLocked) {
        ref.read(biometricProvider.notifier).authenticate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final authState = ref.watch(authProvider);
    final biometricState = ref.watch(biometricProvider);

    Widget homeWidget;

    if (authState is Authenticated) {
      if (biometricState.isEnabled && biometricState.isLocked) {
        homeWidget = const AppLockScreen();
      } else {
        homeWidget = const HomeScreen();
      }
    } else {
      homeWidget = const LoginScreen();
    }

    return MaterialApp(
      title: 'NoteSync',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: homeWidget,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
      ],
    );
  }
}
