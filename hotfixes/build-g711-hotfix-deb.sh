#!/usr/bin/env bash
set -euo pipefail

full_deb=${1:?Usage: build-g711-hotfix-deb.sh FULL_BLUECHERRY_DEB}
package=bluecherry-g711-hotfix
version=3.1.14+g711fix1
work=${2:-build/g711-hotfix}
dist=${3:-dist}

rm -rf "$work"
mkdir -p "$work/full" "$work/root/DEBIAN" \
  "$work/root/usr/lib/$package" \
  "$work/root/usr/share/doc/$package" "$dist"

dpkg-deb -x "$full_deb" "$work/full"
test -x "$work/full/usr/sbin/bc-server"
install -m 0755 "$work/full/usr/sbin/bc-server" \
  "$work/root/usr/lib/$package/bc-server"

cat > "$work/root/DEBIAN/control" <<EOF
Package: $package
Version: $version
Section: admin
Priority: optional
Architecture: amd64
Depends: bluecherry (= 3:3.1.14), coreutils, systemd
Maintainer: Bluecherry G.711 Hotfix <local-hotfix@invalid>
Description: Bluecherry 3.1.14 G.711 recording hotfix
 Replaces only /usr/sbin/bc-server at install time and restores the
 original binary when removed. Keeps H.264 video and PCMA/PCMU audio
 unchanged, selecting the QuickTime MOV muxer for G.711 recordings.
EOF

cat > "$work/root/DEBIAN/preinst" <<'EOF'
#!/bin/sh
set -e
installed=$(dpkg-query -W -f='${Version}' bluecherry 2>/dev/null || true)
case "$installed" in
  3:3.1.14|3:3.1.14-*) ;;
  *)
    echo "This hotfix requires Bluecherry 3:3.1.14; installed: ${installed:-none}" >&2
    exit 1
    ;;
esac
test -x /usr/sbin/bc-server || {
  echo "/usr/sbin/bc-server is missing" >&2
  exit 1
}
exit 0
EOF

cat > "$work/root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
state=/var/lib/bluecherry-g711-hotfix
payload=/usr/lib/bluecherry-g711-hotfix/bc-server
target=/usr/sbin/bc-server

mkdir -p "$state"
if [ ! -f "$state/bc-server.original" ]; then
  cp -a "$target" "$state/bc-server.original"
  sha256sum "$state/bc-server.original" > "$state/bc-server.original.sha256"
fi

systemctl stop bluecherry.service 2>/dev/null || true
install -m 0755 "$payload" "$target"
sha256sum "$target" > "$state/bc-server.hotfix.sha256"
if ! systemctl start bluecherry.service; then
  echo "Hotfix server failed to start; restoring original bc-server" >&2
  install -m 0755 "$state/bc-server.original" "$target"
  systemctl start bluecherry.service 2>/dev/null || true
  exit 1
fi
systemctl --no-pager --full status bluecherry.service || true
exit 0
EOF

cat > "$work/root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
case "$1" in
  remove|deconfigure)
    state=/var/lib/bluecherry-g711-hotfix
    target=/usr/sbin/bc-server
    systemctl stop bluecherry.service 2>/dev/null || true
    if [ -f "$state/bc-server.original" ]; then
      install -m 0755 "$state/bc-server.original" "$target"
    fi
    systemctl start bluecherry.service 2>/dev/null || true
    ;;
esac
exit 0
EOF

cat > "$work/root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
case "$1" in
  purge) rm -rf /var/lib/bluecherry-g711-hotfix ;;
esac
exit 0
EOF

chmod 0755 "$work/root/DEBIAN/preinst" "$work/root/DEBIAN/postinst" \
  "$work/root/DEBIAN/prerm" "$work/root/DEBIAN/postrm"

cat > "$work/root/usr/share/doc/$package/README" <<'EOF'
Bluecherry G.711 recording hotfix
=================================

Scope:
- Native package installation only; no Docker and no relay.
- Requires installed Bluecherry version 3:3.1.14.
- Replaces only /usr/sbin/bc-server at install time.
- Saves the original binary under /var/lib/bluecherry-g711-hotfix/.
- Automatically restores the original if the patched service fails to start.
- Removing this package restores the original binary.

Install:
  sudo dpkg -i bluecherry-g711-hotfix_3.1.14+g711fix1_amd64.deb

Roll back:
  sudo dpkg -r bluecherry-g711-hotfix

Verify:
  systemctl status bluecherry --no-pager
  journalctl -u bluecherry -n 100 --no-pager
EOF

output="$dist/${package}_${version}_amd64.deb"
dpkg-deb --root-owner-group --build "$work/root" "$output"
sha256sum "$output" > "$dist/SHA256SUMS"
dpkg-deb --info "$output"
dpkg-deb --contents "$output"
file "$work/full/usr/sbin/bc-server"
ldd "$work/full/usr/sbin/bc-server"
