# TODO

- [ ] ROCWMMA: Investigate enabling ROCWMMA (fat-attention) for gfx1151
  - Reproduce the DPP instruction error and identify root cause
  - Test combinations of ROCm/clang versions and HIP flags that enable rocWMMA safely
  - Add a guarded build option and CI step that retries with rocWMMA=OFF on failure
  - Document findings and recommended ROCm/toolchain versions in `RECOMMENDATION.md`

