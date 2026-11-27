#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--user" ]; then
  PREFIX="${HOME}/.local"
  OPT_DIR="${PREFIX}/opt/pyure"
  BIN_DIR="${PREFIX}/bin"
  APP_DIR="${PREFIX}/share/applications"
  ICON_DIR="${PREFIX}/share/icons/hicolor/256x256/apps"
  EXEC_PATH="${OPT_DIR}/pyure"
else
  if [ "${EUID}" -ne 0 ]; then
    echo "Запустите с sudo: sudo bash $0 (или установите локально: bash $0 --user)"
    exit 1
  fi
  OPT_DIR="/opt/pyure"
  BIN_DIR="/usr/bin"
  APP_DIR="/usr/share/applications"
  ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
  EXEC_PATH="/usr/bin/pyure"
fi

rm -rf "${OPT_DIR}"
mkdir -p "${OPT_DIR}" "${BIN_DIR}" "${APP_DIR}" "${ICON_DIR}"

cp -a "${SCRIPT_DIR}/pyure" "${OPT_DIR}/pyure"
chmod +x "${OPT_DIR}/pyure"
cp -a "${SCRIPT_DIR}/lib" "${OPT_DIR}/lib"
cp -a "${SCRIPT_DIR}/data" "${OPT_DIR}/data"

ln -sfn "${OPT_DIR}/pyure" "${BIN_DIR}/pyure"
cp -f "${SCRIPT_DIR}/pyure.png" "${ICON_DIR}/pyure.png"
sed "s|^Exec=.*|Exec=${EXEC_PATH} %U|" "${SCRIPT_DIR}/com.pyure.player.desktop" > "${APP_DIR}/com.pyure.player.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "Pyure установлен. Запуск: pyure"
