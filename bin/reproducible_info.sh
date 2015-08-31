#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set -e

ARCH=$(dpkg --print-architecture)
NUM_CPU=$(grep -c '^processor' /proc/cpuinfo)
DATETIME=$(date +'%Y-%m-%d %H:%M %Z')

for i in ARCH NUM_CPU DATETIME ; do
	echo "$i['$HOSTNAME']=\"${!i}\""
done