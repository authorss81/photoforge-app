# Golden image tests

PixelForge's queue, preview and settings panes are covered by golden image
tests, so a layout regression fails in CI instead of reaching a user.

## Where they live

`test_golden/`, deliberately **outside** `test/`.

A plain `flutter test` never runs them. Goldens only pass on the platform they
were generated on, because font rasterization and text shaping differ between
Windows, macOS and Linux. Keeping them inside `test/` would mean every
contributor on Windows or macOS saw a permanently red suite and learned to
ignore it, which is worse than not having the tests.

Two commands, two purposes:

```bash
flutter test              # logic and behaviour, runs everywhere
flutter test test_golden/ # pixel comparison, Linux only
```

## Regenerating

Goldens are generated on **Linux only**:

```bash
# Locally, only if you are on Linux.
flutter test --update-goldens test_golden/

# From anywhere, the supported path.
gh workflow run golden-generate.yml
```

The `golden-generate` workflow runs on `ubuntu-latest`, uploads the images as an
artifact, and you download, **look at every one**, and commit what you approve.

A golden you have not looked at is not a verified change. If you cannot explain
why an image changed, that is a regression, not an update.

Never add `--update-goldens` to a CI job. A golden that can update itself is not
a test.

## What the goldens do and do not cover

They cover geometry: layout, spacing, alignment, overflow, and whether content
appears in the right place at a given width.

They do **not** cover text. Flutter's test font renders every glyph as a filled
box, so the goldens show text as blocks. A changed string looks identical to an
unchanged one. String changes are covered by `find.text` assertions in
`test/preview_test.dart` instead, and `test/preview_test.dart` also asserts real
pixel colours for the split preview.

Neither is a substitute for a human looking at the app.

## Pinning

Goldens are sensitive to the engine's rasteriser, so they depend on the Flutter
version. `FLUTTER_VERSION` is pinned in `build.yml` and `golden-generate.yml`; a
Flutter upgrade means regenerating every golden, on Linux, by hand.