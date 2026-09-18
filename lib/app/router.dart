import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/canvas/canvas_screen.dart';
import '../features/canvas/canvases_screen.dart';
import '../features/graph/graph_screen.dart';
import '../features/home/calendar_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notes/note_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/projects/project_screen.dart';
import '../features/projects/project_work_screen.dart';
import '../features/projects/projects_screen.dart';
import '../theme/kraft_motion.dart';
import 'animated_branch_container.dart';
import 'app_shell.dart';

abstract final class Routes {
  static const home = '/inicio';
  static const calendar = '/inicio/calendario';
  static const projects = '/inicio/proyectos';
  static String project(int id) => '$projects/$id';
  static String projectActivities(int id) => '${project(id)}/actividades';
  static String projectRequirements(int id) => '${project(id)}/requerimientos';
  static String projectRequirement(int projectId, int itemId) =>
      '${projectRequirements(projectId)}?item=$itemId';
  static const canvas = '/lienzo';
  static String canvasEditor(int id) => '/lienzo/$id';
  static const notes = '/notas';
  static String noteEditor(int id) => '/notas/$id';
  static const graph = '/grafo';
  static const settings = '/ajustes';
}

/// Subpantallas: entran desde la derecha con rebote corto.
Page<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: KraftMotion.slow,
    reverseTransitionDuration: KraftMotion.fast,
    transitionsBuilder: (context, animation, secondary, child) {
      if (KraftMotion.reduced(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: KraftMotion.pop,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.5),
        ),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Navegador raíz: el modo lienzo se abre encima de la barra inferior.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Entrar en modo lienzo: la pantalla crece desde el centro.
Page<void> _canvasPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: KraftMotion.slow,
    reverseTransitionDuration: KraftMotion.base,
    transitionsBuilder: (context, animation, secondary, child) {
      if (KraftMotion.reduced(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: KraftMotion.settle,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// El proyecto se desplaza sin fundido: al venir desde Inicio no deja ver un
/// fotograma vacío mientras el navegador anidado compone su nueva página.
Page<void> _projectPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: KraftMotion.base,
    reverseTransitionDuration: KraftMotion.fast,
    transitionsBuilder: (context, animation, secondary, child) {
      if (KraftMotion.reduced(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: KraftMotion.settle,
        reverseCurve: Curves.easeIn,
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// El router de la app. Se expone para que el asistente —que vive por encima del navegador,
/// en su propio `Overlay`— también pueda abrir pantallas.
final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) => _slidePage(state, const SettingsScreen()),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            AnimatedBranchContainer(
              currentIndex: shell.currentIndex,
              children: children,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'calendario',
                    pageBuilder: (_, state) =>
                        _slidePage(state, const CalendarScreen()),
                  ),
                  GoRoute(
                    path: 'proyectos',
                    pageBuilder: (_, state) =>
                        _slidePage(state, const ProjectsScreen()),
                    routes: [
                      GoRoute(
                        path: ':id',
                        pageBuilder: (_, state) => _projectPage(
                          state,
                          ProjectScreen(
                            projectId:
                                int.tryParse(
                                  state.pathParameters['id'] ?? '',
                                ) ??
                                0,
                          ),
                        ),
                        routes: [
                          GoRoute(
                            path: 'actividades',
                            pageBuilder: (_, state) => _slidePage(
                              state,
                              ProjectWorkScreen(
                                projectId:
                                    int.tryParse(
                                      state.pathParameters['id'] ?? '',
                                    ) ??
                                    0,
                                requirements: false,
                              ),
                            ),
                          ),
                          GoRoute(
                            path: 'requerimientos',
                            pageBuilder: (_, state) => _slidePage(
                              state,
                              ProjectWorkScreen(
                                projectId:
                                    int.tryParse(
                                      state.pathParameters['id'] ?? '',
                                    ) ??
                                    0,
                                requirements: true,
                                focusItemId: int.tryParse(
                                  state.uri.queryParameters['item'] ?? '',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.canvas,
                builder: (_, _) => const CanvasesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (_, state) => _canvasPage(
                      state,
                      CanvasScreen(
                        key: ValueKey(state.pathParameters['id']),
                        canvasId: int.parse(state.pathParameters['id']!),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.notes,
                builder: (_, _) => const NotesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (_, state) => _canvasPage(
                      state,
                      NoteScreen(
                        key: ValueKey('note-${state.pathParameters['id']}'),
                        noteId: int.parse(state.pathParameters['id']!),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.graph,
                builder: (_, _) => const GraphScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
