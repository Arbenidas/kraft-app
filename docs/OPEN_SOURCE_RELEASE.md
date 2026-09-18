# Open-source release checklist

Use this checklist before creating the public GitHub repository.

## Repository

- [ ] Create an empty GitHub repository and use `main` as its default branch.
- [ ] Add the repository URL to the README clone command and any desired badges.
- [ ] Enable GitHub Actions and require the `CI / test` check before merging.
- [ ] Configure a private security contact in GitHub's Security settings.
- [ ] Optionally enable Dependabot and GitHub Discussions.

## Privacy and assets

- [ ] Confirm permission to redistribute every asset under `assets/` and `design/`.
- [ ] Replace or explicitly approve `assets/images/avatar.jpg` if it is a personal photo.
- [ ] Verify that screenshots do not reveal personal tasks, notes, tokens, device names or network addresses.
- [ ] Confirm no local database, keychain export, `.env` file, signing certificate or provisioning profile is staged.

## Apple distribution

- [ ] Change `com.arbe.kraft` to your own bundle identifier before signing a public build.
- [ ] Create WidgetKit extension targets and an App Group only when you have a signed Apple Developer team; the checked-in widget sources alone are not distributable extensions.

## Verification

```bash
git status --ignored
dart format --output=none --set-exit-if-changed lib test packages
flutter analyze --no-fatal-infos
flutter test
```
