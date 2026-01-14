# TODO

- [x] Script cleanup: standardize SUDO_CMD usage across all scripts, fix typos in 05-package-rocm.sh
- [x] Testing: verified pipeline runs in toolbox (01.sh completed, 02.sh installing ROCm), Docker build initiated
- [ ] ROCWMMA: Investigate enabling ROCWMMA (fat-attention) for gfx1151
  - Reproduce the DPP instruction error and identify root cause
  - Test combinations of ROCm/clang versions and HIP flags that enable rocWMMA safely
  - Add a guarded build option and CI step that retries with rocWMMA=OFF on failure
  - Document findings and recommended ROCm/toolchain versions in `RECOMMENDATION.md`

