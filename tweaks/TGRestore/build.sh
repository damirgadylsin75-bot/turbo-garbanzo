#!/bin/bash
# Build TGRestore into a rootless-jailbreak .deb.
# Run on macOS with Xcode + Theos installed.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${THEOS:-}" ]; then
    echo "THEOS is not set. Install Theos and run: THEOS=/opt/theos ./build.sh"
    exit 1
fi

make clean
make package THEOS_PACKAGE_SCHEME=rootless "$@"

echo
echo "Built package:"
ls -1 .theos/*.deb 2>/dev/null || true
