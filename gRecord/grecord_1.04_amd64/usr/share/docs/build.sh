#!/bin/bash
SRC="gRecord.bas"
OUT="grecord"
FLAGS="-s gui -l gtk-3 -l gdk-3 -l glib-2.0 -l gobject-2.0 -l X11"
echo "Compiling $SRC..."
# Pass the flags directly to fbc
fbc "$SRC" -x "$OUT" $FLAGS

if [ $? -ne 0 ]; then
    echo "Build failed."
    exit 1
fi

# Packaging
VERSION="1.04"
ARCH=$(dpkg --print-architecture)
PKG_NAME="grecord"
DEB_DIR="${PKG_NAME}_${VERSION}_${ARCH}"

echo "Building Debian package structure in $DEB_DIR..."

# Clean up previous build
rm -rf "$DEB_DIR"
rm -f "${DEB_DIR}.deb"

# Create directories
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/docs"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/scalable/apps"

# Copy binary
cp "$OUT" "$DEB_DIR/usr/bin/"
# and source
cp gRecord.bas "$DEB_DIR/usr/share/docs"
cp build.sh "$DEB_DIR/usr/share/docs" #and this file
# Create control file
cat > "$DEB_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: Eric Sebasta <allpraise@gma1l.com>
Depends: libgtk-3-0, alsa-utils, ffmpeg, wf-recorder
Section: video
Priority: optional
Description: gRecord - GTK Screen Recorder Frontend
 A simple tray-based screen recorder that uses ffmpeg (for X11) or wf-recorder (for Wayland). Written in FreeBASIC.
 Source in /usr/share/docs/gRecord
EOF

# Create .desktop file
cat > "$DEB_DIR/usr/share/applications/grecord.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=gRecord
Comment=GTK Screen Recorder Frontend
Exec=grecord
Icon=grecord
Terminal=false
Categories=AudioVideo;Player;Recorder;
EOF

# Copy icon (assuming grmd.svg exists in current dir)
if [ -f "gRecord.svg" ]; then
    cp "gRecord.svg" "$DEB_DIR/usr/share/icons/hicolor/scalable/apps/grecord.svg"
else
    echo "Warning: grmd.svg not found. Generating placeholder icon."
    cat > "$DEB_DIR/usr/share/icons/hicolor/scalable/apps/grecord.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <circle cx="24" cy="24" r="22" fill="#cc0000" />
</svg>
EOF
fi

# Create post-install and post-remove scripts for better desktop integration
cat > "$DEB_DIR/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ -x "/usr/bin/gtk-update-icon-cache" ]; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor
fi
if [ -x "/usr/bin/update-desktop-database" ]; then
    update-desktop-database -q
fi
exit 0
EOF

chmod 0755 "$DEB_DIR/DEBIAN/postinst"
# postrm is identical to postinst for this case
cp "$DEB_DIR/DEBIAN/postinst" "$DEB_DIR/DEBIAN/postrm"

# Build .deb
dpkg-deb --root-owner-group --build "$DEB_DIR"

echo "Done. Package created: ${DEB_DIR}.deb"
