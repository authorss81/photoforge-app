# Benchmarks

Measured, never estimated. Run explicitly:

```bash
flutter test benchmark/
```

It is a separate CI job that uploads its table as an artifact. It is never a
required check and never blocks a merge, because it takes tens of minutes.

## Method

- Sources carry high-frequency content (gradient plus hash detail) so the
  encoders do real work. A smooth gradient would compress trivially and hide
  every cost that matters.
- Every cell is a median over five iterations with the worst deviation
  reported. A single run is noise.
- Sizes are approximate megapixels of the *source*; outputs are 1080px.

## Baseline

Runner: GitHub `ubuntu-latest` CI, Flutter 3.44.8. Updated by copying the
table from the benchmark job artifact.

| source | fit-1080 jpeg-q85 | fit-1080 webp-q80 | crop-1080 jpeg-q85 | crop-1080 webp-q80 |
| --- | --- | --- | --- | --- |
| 1 MP | pending first CI run | pending first CI run | pending first CI run | pending first CI run |
| 4 MP | pending first CI run | pending first CI run | pending first CI run | pending first CI run |
| 16 MP | pending first CI run | pending first CI run | pending first CI run | pending first CI run |

## Rules for performance work

- Quote this table before and after. A speedup without both numbers is a story.
- Update the table in the same commit as the change.
- Never report an estimate as a measurement.
