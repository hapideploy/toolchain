#!/usr/bin/env bash

echo 'Update available packages'

apt update

echo 'Upgrade all installed packages if possible'

apt upgrade -y

echo 'Clear out old, useless package files (.deb) from local APT cache'

apt autoclean

echo 'Remove unused packages'

apt autoremove

if [ -f /var/run/reboot-required ]; then
    reboot
fi
