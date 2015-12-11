#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# configure mock for a given release and architecture
#

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

if [ -z "$1" ] || [ -z "$2" ] ; then
	echo "Need release and architecture as params."
	exit 1
fi
RELEASE=$1
ARCH=$2

echo "$(date -u) - showing setup."
dpkg -l mock
id
echo "$(date -u) - starting to cleanly configure mock for $RELEASE on $ARCH."
mock -r $RELEASE-$ARCH --resultdir=. --clean
mock -r $RELEASE-$ARCH --resultdir=. --init
echo "$(date -u) - mock configured for $RELEASE on $ARCH."
