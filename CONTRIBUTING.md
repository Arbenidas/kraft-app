# Contributing to KRAFT

Thanks for contributing. Small, well-scoped pull requests are the easiest to review.

## Development setup

1. Fork the repository and create a branch from `main`.
2. Install the Flutter version described in the README.
3. Run `flutter pub get`.
4. Make the change with tests where practical.
5. Run the quality checks before opening a pull request.

```bash
dart format --output=none --set-exit-if-changed lib test packages
flutter analyze --no-fatal-infos
flutter test
```

If a change touches Drift tables, regenerate the database code:

```bash
dart run build_runner build --delete-conflicting-outputs --force-jit
```

## Pull requests

- Explain the user problem and the solution.
- Keep unrelated formatting and refactors out of the same pull request.
- Add or update tests for behavior changes.
- Include screenshots for visual changes, covering a narrow iPad-sized layout when relevant.
- Never commit API keys, bearer tokens, databases, provisioning profiles or personal workspace data.

## Issues

Use GitHub issues for reproducible bugs and focused feature proposals. Security vulnerabilities must follow [SECURITY.md](SECURITY.md).
