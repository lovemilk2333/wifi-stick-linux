#!/bin/sh
set -eu

apt_mirror=${1:?missing Debian mirror URL}
timezone=${2:?missing target timezone}
language=${3:?missing display language}
apt_mirror=${apt_mirror%/}

case "$timezone" in
  *..*|/*|*[!A-Za-z0-9_+/-]*)
    echo "Invalid timezone: $timezone" >&2
    exit 1
    ;;
esac

case "$language" in
  zh_cn)
    target_locale=zh_CN.UTF-8
    ;;
  en_us)
    target_locale=en_US.UTF-8
    ;;
  *)
    echo "Unsupported display language: $language" >&2
    exit 1
    ;;
esac

rm -f /*dbg*.deb
rm -rf /etc/apt/sources.list.d/*

cat > /etc/apt/sources.list <<EOF
deb $apt_mirror bullseye main contrib non-free
deb $apt_mirror bullseye-updates main contrib non-free
# The old target image needs an initial certificate refresh.
# deb https://security.debian.org/debian-security bullseye-security main contrib non-free
EOF

cat > /etc/systemd/system/rc-local.service <<'EOF'
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/rc.local <<'EOF'
#!/bin/sh -e
exit 0
EOF

chmod +x /etc/rc.local
systemctl daemon-reload
systemctl enable rc-local
apt -o Acquire::https::Verify-Peer=false update
apt -o Acquire::https::Verify-Peer=false install -y \
  ca-certificates locales tzdata usbutils curl wget fdisk net-tools nano
sed -i "/^# $target_locale UTF-8$/c\\$target_locale UTF-8" /etc/locale.gen
grep -qxF "$target_locale UTF-8" /etc/locale.gen || echo "$target_locale UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG="$target_locale"
[ -f "/usr/share/zoneinfo/$timezone" ] || {
  echo "Unsupported timezone: $timezone" >&2
  exit 1
}
ln -snf "/usr/share/zoneinfo/$timezone" /etc/localtime
echo "$timezone" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
sed -i '/PermitRootLogin /c PermitRootLogin yes' /etc/ssh/sshd_config
sed -i '/PasswordAuthentication /c PasswordAuthentication yes' /etc/ssh/sshd_config
grep -q '^PermitRootLogin ' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication ' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
dpkg -l | awk '/linux-(headers|image)/ {print $2}' | xargs -r dpkg -P
dpkg -i /*.deb
rm -f /*.deb
