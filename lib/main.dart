import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'data/db/database.dart';
import 'data/providers.dart';
import 'features/ai/ai_providers.dart';
import 'features/voice/voice_overlay.dart';
import 'features/forms/entity_sheets.dart';
import 'platform/widget_sync.dart';
import 'theme/kraft_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.onDevice();
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const KraftApp(),
    ),
  );
}

class KraftApp extends ConsumerStatefulWidget {
  const KraftApp({super.key});

  @override
  ConsumerState<KraftApp> createState() => _KraftAppState();
}

class _KraftAppState extends ConsumerState<KraftApp>
    with WidgetsBindingObserver {
  late final _router = ref.read(routerProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // La IA puede abrir lienzos en pantalla; el servidor MCP arranca si el usuario lo dejó activado.
    ref.read(canvasBridgeProvider).openHandler = (id) async =>
        _router.go(Routes.canvasEditor(id));
    ref.read(noteBridgeProvider).openHandler = (id) async =>
        _router.go(Routes.noteEditor(id));
    ref
        .read(voiceControllerProvider)
        .tools
        .openViewHandler = (view, projectId, {int? requirementId}) async {
      switch (view) {
        case 'home':
          _router.go(Routes.home);
        case 'calendar':
          _router.go(Routes.calendar);
        case 'projects':
          _router.go(Routes.projects);
        case 'requirement' || 'requirements':
          if (requirementId != null && projectId != null) {
            _router.go(Routes.projectRequirement(projectId, requirementId));
          } else if (projectId != null) {
            _router.go(Routes.projectRequirements(projectId));
          }
        case 'activities':
          if (projectId != null) {
            _router.go(Routes.projectActivities(projectId));
          }
        case 'project':
          if (requirementId != null && projectId != null) {
            _router.go(Routes.projectRequirement(projectId, requirementId));
          } else {
            _router.go(Routes.project(projectId!));
          }
        case 'notes':
          _router.go(Routes.notes);
        case 'canvases':
          _router.go(Routes.canvas);
        case 'graph':
          _router.go(Routes.graph);
        case 'settings':
          _router.push(Routes.settings);
        case 'close':
          final navigator = _router.routerDelegate.navigatorKey.currentState;
          if (navigator != null && navigator.canPop()) navigator.pop();
        default:
          return;
      }
    };
    ref.read(mcpControllerProvider);
    ref.read(reminderServiceProvider);
    WidgetSync.registerCaptureHandler(() async {
      final context = _router.routerDelegate.navigatorKey.currentContext;
      if (context != null) await showCaptureMenu(context, ref);
    });
  }

  /// Si el iPad o el Mac pasan a modo oscuro y estamos en "como el sistema", se repinta.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // El router lo cierra su provider.

  @override
  Widget build(BuildContext context) {
    ref.listen(
      tasksProvider,
      (_, next) => WidgetSync.sync(
        tasks: next.valueOrNull ?? const [],
        work: ref.read(allWorkItemsProvider).valueOrNull ?? const [],
      ),
    );
    ref.listen(
      allWorkItemsProvider,
      (_, next) => WidgetSync.sync(
        tasks: ref.read(tasksProvider).valueOrNull ?? const [],
        work: next.valueOrNull ?? const [],
      ),
    );
    // La paleta es global (la leen 500 sitios sin pasar por el contexto), así que se fija
    // antes de construir y la app entera se redibuja cuando cambia.
    final theme = ref.watch(themeProvider);
    final system =
        MediaQuery.maybePlatformBrightnessOf(context) ??
        View.of(context).platformDispatcher.platformBrightness;
    final brightness = theme.brightness(system);

    return MaterialApp.router(
      title: 'KRAFT',
      themeAnimationDuration: Duration.zero,
      debugShowCheckedModeBanner: false,
      theme: KraftTheme.of(brightness),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: (context, child) =>
          VoiceOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
