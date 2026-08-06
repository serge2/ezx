#!/bin/sh
# Remove the ezx installation (tarball install.sh counterpart). Run as root.
set -u

if [ "$(id -u)" != "0" ]; then
    echo "Please run as root: sudo ./uninstall.sh" >&2
    exit 1
fi

rm -rf /opt/ezx
rm -f /usr/local/bin/ezx
rm -f /usr/share/applications/ezx.desktop
rm -f /usr/share/pixmaps/ezx.png

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi

echo "ezx removed"
