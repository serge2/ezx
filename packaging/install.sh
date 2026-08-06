#!/bin/sh
# Install the ezx tarball payload into /opt/ezx and register the desktop entry.
# Run from the unpacked tarball directory as root: sudo ./install.sh
set -u

if [ "$(id -u)" != "0" ]; then
    echo "Please run as root: sudo ./install.sh" >&2
    exit 1
fi

rm -rf /opt/ezx
mkdir -p /opt/ezx
cp -a bin lib releases erts-* /opt/ezx/
ln -sf /opt/ezx/bin/ezx-launch /usr/local/bin/ezx
install -m 644 ezx.desktop /usr/share/applications/ezx.desktop
install -m 644 ezx.png /usr/share/pixmaps/ezx.png

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi

echo "ezx installed to /opt/ezx. Menu entry: Applications -> ezx"
