#!/usr/bin/env bash
### every exit != 0 fails the script
set -e

echo "Install some common tools for further installation"
apt-get update 
apt-get install -y vim wget net-tools locales bzip2 git \
    htop locales python-numpy #used for websockify/novnc
apt-get clean -y

echo "generate locales for C.UTF-8" #was en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
locale-gen C.UTF-8
dpkg-reconfigure locales