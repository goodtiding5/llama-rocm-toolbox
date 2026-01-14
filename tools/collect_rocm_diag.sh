#!/usr/bin/env bash
set -euo pipefail

echo "====1. rocminfo file===="
ls -l /opt/rocm/bin/rocminfo || true

echo "\n====2. run rocminfo (no extra env)===="
/opt/rocm/bin/rocminfo 2>&1 | sed -n '1,200p' || true

echo "\n====3. ldd on rocminfo===="
ldd /opt/rocm/bin/rocminfo 2>&1 | sed -n '1,200p' || true

echo "\n====4. ldconfig listing for ROCm libs===="
ldconfig -p 2>/dev/null | grep -E 'libhip|librocclr|librocm' || true

echo "\n====5. try with LD_LIBRARY_PATH===="
LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64 /opt/rocm/bin/rocminfo 2>&1 | sed -n '1,200p' || true

echo "\n====6. PATH and LD_LIBRARY_PATH in this shell===="
echo PATH=$PATH
echo LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}

echo "\n====7. device nodes===="
ls -l /dev/kfd /dev/dri || true

echo "\n====8. kernel modules (host) - may be empty inside container===="
lsmod | egrep 'amdgpu|kfd' || true

echo "\n====9. strace attempt (captures missing files or permissions)====
"
if command -v strace >/dev/null 2>&1; then
  echo "Running strace (may require strace installed)"
  strace -f -o /tmp/rocminfo.strace /opt/rocm/bin/rocminfo || true
  echo "---- strace tail ----"
  tail -n 100 /tmp/rocminfo.strace || true
else
  echo "strace not available; skipping." 
fi

exit 0
