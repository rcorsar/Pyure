#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <bundle_dir> [out_dir]}"
BUNDLE_DIR="${2:?Usage: $0 <version> <bundle_dir> [out_dir]}"
OUT_DIR="${3:-dist}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DATE="$(date +%s)"

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

if [ ! -x "${BUNDLE_DIR}/pyure" ]; then
  echo "Missing Linux bundle binary at ${BUNDLE_DIR}/pyure"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

copy_bundle_tree() {
  local root="$1"
  mkdir -p \
    "${root}/opt/pyure" \
    "${root}/usr/bin" \
    "${root}/usr/share/applications" \
    "${root}/usr/share/icons/hicolor/256x256/apps"

  cp -a "${BUNDLE_DIR}/." "${root}/opt/pyure/"
  chmod 755 "${root}/opt/pyure/pyure"
  ln -sfn /opt/pyure/pyure "${root}/usr/bin/pyure"
  cp -f "${SCRIPT_DIR}/com.pyure.player.desktop" "${root}/usr/share/applications/com.pyure.player.desktop"
  cp -f "${SCRIPT_DIR}/pyure.png" "${root}/usr/share/icons/hicolor/256x256/apps/pyure.png"
}

echo "==> Packaging .tar.gz..."
TAR_STAGE="${WORK_DIR}/tar/pyure-${VERSION}-linux-x64"
mkdir -p "${TAR_STAGE}"
cp -a "${BUNDLE_DIR}/." "${TAR_STAGE}/"
chmod 755 "${TAR_STAGE}/pyure"
cp -f "${SCRIPT_DIR}/com.pyure.player.desktop" "${TAR_STAGE}/com.pyure.player.desktop"
cp -f "${SCRIPT_DIR}/pyure.png" "${TAR_STAGE}/pyure.png"
cp -f "${SCRIPT_DIR}/install.sh" "${TAR_STAGE}/install.sh"
chmod 755 "${TAR_STAGE}/install.sh"
tar -C "${WORK_DIR}/tar" -czf "${OUT_DIR}/Pyure-${VERSION}-linux-x64.tar.gz" "pyure-${VERSION}-linux-x64"

echo "==> Packaging .deb (Debian / Ubuntu)..."
DEB_ROOT="${WORK_DIR}/deb"
copy_bundle_tree "${DEB_ROOT}"
mkdir -p "${DEB_ROOT}/DEBIAN"
INSTALLED_KB="$(du -sk "${DEB_ROOT}/opt/pyure" | awk '{print $1}')"
cat > "${DEB_ROOT}/DEBIAN/control" <<EOF
Package: pyure
Version: ${VERSION}
Section: sound
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_KB}
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1, xdg-desktop-portal
Recommends: xdg-desktop-portal-gtk | xdg-desktop-portal-kde, zenity
Maintainer: Pyure <https://github.com/rcorsar/Pyure>
Homepage: https://github.com/rcorsar/Pyure
Description: Offline MP3 player for Linux, Windows, and Android
 Local offline MP3 player without internet permissions or ads.
EOF
cat > "${DEB_ROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF
chmod 755 "${DEB_ROOT}/DEBIAN/postinst"
fakeroot dpkg-deb --build "${DEB_ROOT}" "${OUT_DIR}/Pyure-${VERSION}-linux-x64.deb"

echo "==> Packaging .rpm (Fedora)..."
RPM_TOP="${WORK_DIR}/rpmbuild"
mkdir -p "${RPM_TOP}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
RPM_SRC="${WORK_DIR}/rpm_payload"
copy_bundle_tree "${RPM_SRC}"

cat > "${RPM_TOP}/SPECS/pyure.spec" <<EOF
%global debug_package %{nil}
%global _build_id_links none
%define __strip /bin/true

Name:           pyure
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Offline MP3 player
License:        MIT
URL:            https://github.com/rcorsar/Pyure
AutoReqProv:    no
Requires:       gtk3
Requires:       (mpv-libs or libmpv or mpv)
Requires:       xdg-desktop-portal

%description
Pyure — offline local MP3 player without internet access or ads.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ${RPM_SRC}/. %{buildroot}/

%files
/opt/pyure
/usr/bin/pyure
/usr/share/applications/com.pyure.player.desktop
/usr/share/icons/hicolor/256x256/apps/pyure.png

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

rpmbuild --define "_topdir ${RPM_TOP}" --target x86_64 -bb "${RPM_TOP}/SPECS/pyure.spec"
BUILT_RPM="$(find "${RPM_TOP}/RPMS" -name '*.rpm' | head -n1)"
if [ -z "${BUILT_RPM}" ]; then
  echo "RPM build failed: output RPM not found"
  exit 1
fi
cp -f "${BUILT_RPM}" "${OUT_DIR}/Pyure-${VERSION}-linux-x64.rpm"

echo "==> Packaging .pkg.tar.zst (Arch Linux)..."
ARCH_ROOT="${WORK_DIR}/arch"
copy_bundle_tree "${ARCH_ROOT}"
INSTALLED_BYTES="$(du -sb "${ARCH_ROOT}" | awk '{print $1}')"
cat > "${ARCH_ROOT}/.PKGINFO" <<EOF
pkgname = pyure
pkgbase = pyure
pkgver = ${VERSION}-1
pkgdesc = Pyure offline MP3 player
url = https://github.com/rcorsar/Pyure
builddate = ${BUILD_DATE}
packager = Pyure CI <noreply@github.com>
size = ${INSTALLED_BYTES}
arch = x86_64
license = MIT
depend = gtk3
depend = mpv
depend = xdg-desktop-portal
optdepend = zenity: fallback folder picker dialog
optdepend = kdialog: KDE fallback folder picker dialog
EOF

(
  cd "${ARCH_ROOT}"
  chmod -R a+rX opt usr
  if command -v bsdtar >/dev/null 2>&1; then
    env LANG=C bsdtar -czf .MTREE --format=mtree \
      --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
      --uname=root --gname=root \
      .PKGINFO opt usr
    env LANG=C bsdtar -c --uname=root --gname=root \
      .PKGINFO .MTREE opt usr | zstd -q -19 -T0 -o "${OUT_DIR}/Pyure-${VERSION}-linux-x64.pkg.tar.zst"
  else
    tar --sort=name --owner=root:0 --group=root:0 --numeric-owner \
      -c .PKGINFO opt usr | zstd -q -19 -T0 -o "${OUT_DIR}/Pyure-${VERSION}-linux-x64.pkg.tar.zst"
  fi
)

ls -lh "${OUT_DIR}"
