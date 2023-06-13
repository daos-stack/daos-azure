#!/usr/bin/env bash

dnf -y install epel-release
dnf -y install python3.11 python3.11-pip ansible-core dnf-plugins-core
alternatives --set python3 /usr/bin/python3.11
dnf config-manager --save --setopt=fastestmirror=True
dnf config-manager --set-enabled powertools
