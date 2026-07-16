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

import 'firebase_options.dart';
import 'core/notifications/notification_manager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'domain/repository/note_repository.dart';
import 'presentation/screens/note_editor/note_editor_screen.dart';
import 'package:home_widget/home_widget.dart';
import 'presentation/providers/notes_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationManager.init();
  
  // Load Dotenv Configuration first so environment variables are available during Firebase options resolution
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Failed to load .env: $e');
  }

  // Initialize Firebase (safely catches exceptions if local configurations are missing)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, stack) {
    debugPrint('Firebase initialization failed: $e');
    debugPrint('Stack trace: $stack');
  }

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
  StreamSubscription<String?>? _notificationSubscription;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupBackgroundSyncListeners();
    _setupNotificationClickListener();
    _setupWidgetClickListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _notificationSubscription?.cancel();
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

  void _setupNotificationClickListener() {
    _notificationSubscription = NotificationManager.selectNotificationStream.stream.listen(_navigateToNote);

    // Handle launch from terminated state via notification click
    FlutterLocalNotificationsPlugin().getNotificationAppLaunchDetails().then((details) {
      if (details != null && details.didNotificationLaunchApp) {
        final payload = details.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateToNote(payload);
        }
      }
    });
  }

  void _navigateToNote(String? noteId) async {
    if (noteId == null || noteId.isEmpty) return;
    final repo = di.sl<NoteRepository>();
    final result = await repo.getNoteById(noteId);
    result.fold(
      (note) {
        if (note != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
          );
        }
      },
      (_) {},
    );
  }

  void _setupWidgetClickListener() {
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      _handleWidgetClick(uri);
    });

    HomeWidget.widgetClicked.listen((uri) {
      _handleWidgetClick(uri);
    });
  }

  void _handleWidgetClick(Uri? uri) async {
    if (uri != null) {
      if (uri.scheme == 'notesync') {
        if (uri.host == 'quick_capture') {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (context) => const NoteEditorScreen()),
          );
        } else if (uri.host == 'notes') {
          final noteId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
          if (noteId != null) {
            final repo = di.sl<NoteRepository>();
            final result = await repo.getNoteById(noteId);
            result.fold(
              (note) {
                if (note != null) {
                  navigatorKey.currentState?.push(
                    MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
                  );
                }
              },
              (_) {},
            );
          }
        }
      }
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
    ref.watch(widgetSyncProvider);
    final themeState = ref.watch(themeProvider);
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
      navigatorKey: navigatorKey,
      title: 'NoteSync',
      theme: AppTheme.buildTheme(themeState, isDark: false),
      darkTheme: AppTheme.buildTheme(themeState, isDark: true),
      themeMode: themeState.themeMode,
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
