#!/usr/bin/env bash
set -euo pipefail

APP_NAME="musify"
APP_DISPLAY_NAME="Musify"
BUNDLE_DIR="build/linux/x64/release/bundle"
DIST_DIR="build/desktop-artifacts"
VERSION="$(sed -n 's/^version: \([^ +]*\).*/\1/p' pubspec.yaml)"
DEB_REVISION="${DEB_REVISION:-1}"
PACKAGE_VERSION="${VERSION}-${DEB_REVISION}"
PACKAGE_ROOT="build/linux-package/${APP_NAME}_${PACKAGE_VERSION}_amd64"
APP_DIR="${PACKAGE_ROOT}/usr/lib/${APP_NAME}"
if [[ ! -x "${BUNDLE_DIR}/${APP_NAME}" ]]; then
  echo "Linux release bundle not found at ${BUNDLE_DIR}" >&2
  exit 1
fi

rm -rf "${DIST_DIR}" "${PACKAGE_ROOT}"
mkdir -p "${DIST_DIR}" "${APP_DIR}" \
  "${PACKAGE_ROOT}/DEBIAN" \
  "${PACKAGE_ROOT}/usr/bin" \
  "${PACKAGE_ROOT}/usr/share/applications" \
  "${PACKAGE_ROOT}/usr/share/icons/hicolor/192x192/apps"

cp -R "${BUNDLE_DIR}/." "${APP_DIR}/"
ln -s "/usr/lib/${APP_NAME}/${APP_NAME}" "${PACKAGE_ROOT}/usr/bin/${APP_NAME}"

if [[ -f "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" ]]; then
  install -m 0644 "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
    "${PACKAGE_ROOT}/usr/share/icons/hicolor/192x192/apps/${APP_NAME}.png"
fi

install -m 0644 "linux/musify.desktop" "${PACKAGE_ROOT}/usr/share/applications/${APP_NAME}.desktop"

INSTALLED_SIZE="$(du -sk "${PACKAGE_ROOT}/usr" | cut -f1)"
cat > "${PACKAGE_ROOT}/DEBIAN/control" <<CONTROL
Package: ${APP_NAME}
Version: ${PACKAGE_VERSION}
Section: sound
Priority: optional
Architecture: amd64
Maintainer: Musify Desktop Port <noreply@github.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libstdc++6, libmpv2 | libmpv1 | libmpv-dev
Description: Music streaming app made in Flutter
 Unofficial desktop port of Musify for Linux.
CONTROL

dpkg-deb --root-owner-group --build "${PACKAGE_ROOT}" "${DIST_DIR}/Musify-linux-x64.deb"
tar -C "${BUNDLE_DIR}" -czf "${DIST_DIR}/Musify-linux-x64.tar.gz" .
