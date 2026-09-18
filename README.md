# KRAFT

KRAFT is a local-first creative workspace built with Flutter for macOS and iPadOS. It brings projects, requirements, tasks, notes, a visual canvas and calendar planning into one focused workspace.

> The application is in active development. Data stays on the device today; multi-device sync is not implemented yet.

## What it includes

- Projects with requirements, acceptance criteria and task hierarchies.
- A task view that nests subtasks under their parent requirement.
- Weekly and monthly calendar planning with drag-and-drop scheduling.
- Markdown notes with tables, callouts and framed code blocks.
- An infinite canvas for diagrams, sketching and visual planning.
- Configurable AI chat and a local MCP server that can manage projects, requirements, tasks, notes and canvases.
- Optional, experimental web discovery using public HTML search results. It is disabled by default and clearly warns before sending a query to the Internet.

## Privacy and AI

KRAFT stores workspace data in a local SQLite database. Provider credentials are saved in the operating system secure store and are never committed to this repository.

AI providers and the optional web-discovery feature make network requests only after the user configures or enables them. Do not include sensitive workspace content in third-party prompts or web searches unless you are comfortable sharing it with that service.

## Requirements

- Flutter 3.47 or newer (Dart 3.10+)
- Xcode for macOS and iPadOS builds
- An iPad simulator/device or a Mac for development

## Getting started

```bash
git clone https://github.com/Arbenidas/kraft-app.git
cd kraft-app
flutter pub get
flutter run -d macos
```

To target a connected device or simulator, first inspect the available targets:

```bash
flutter devices
flutter run -d <device-id>
```

## Quality checks

```bash
dart format --output=none --set-exit-if-changed lib test packages
flutter analyze --no-fatal-infos
flutter test
```

Drift generated code must be refreshed after modifying `lib/data/db/tables.dart`:

```bash
dart run build_runner build --delete-conflicting-outputs --force-jit
```

When the database schema changes, also increment `schemaVersion` and add the corresponding migration in `lib/data/db/database.dart`.

## Project layout

```text
lib/
  app/          Routing and application shell
  data/         Drift/SQLite database, repositories and Riverpod providers
  features/     Product features: projects, notes, canvas, calendar, AI and settings
  platform/     Native-platform bridges
  theme/        Design tokens and theme controllers
  widgets/      Shared UI components
packages/
  kraft_web_discovery/  Experimental, replaceable public HTML search adapter
test/           Unit and widget tests
docs/           Product and implementation notes
```

## MCP

KRAFT can expose a local MCP endpoint from **Connect AI** in the app. It uses a bearer token and is intended for trusted local networks. The app must remain in the foreground on iPadOS because the operating system suspends network servers in the background.

The MCP tool set can read and manage projects, requirements, subtasks, notes and canvases. It can also request opening or closing a current KRAFT view when the app is active.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request, and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

For security issues, use the process in [SECURITY.md](SECURITY.md) instead of public issue comments.

## License

KRAFT is available under the [MIT License](LICENSE).

## Before publishing a fork

Review [docs/OPEN_SOURCE_RELEASE.md](docs/OPEN_SOURCE_RELEASE.md). In particular, replace or confirm that you have permission to publish the sample images, including `assets/images/avatar.jpg`, before making a repository public.
