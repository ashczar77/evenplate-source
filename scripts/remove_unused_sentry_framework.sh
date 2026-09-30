#!/bin/sh
set -eu

app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
framework="${app}/Frameworks/Sentry.framework"
[ -d "$framework" ] || exit 0

binary="${framework}/Sentry"
[ -f "$binary" ] || exit 1

if [ "$(stat -f %z "$binary")" -ge 102400 ]; then
  echo "Sentry.framework is not the expected empty Swift package wrapper" >&2
  exit 1
fi

for candidate in "$app/$EXECUTABLE_NAME" "$app"/Frameworks/*.framework/*; do
  [ -f "$candidate" ] || continue
  [ "$candidate" = "$binary" ] && continue
  if xcrun otool -L "$candidate" 2>/dev/null | grep -q '@rpath/Sentry.framework/Sentry'; then
    echo "Sentry.framework is a runtime dependency of $candidate" >&2
    exit 1
  fi
done

rm -rf "$framework"
echo "Removed unused Sentry Swift package wrapper"
