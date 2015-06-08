#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# build for different architectures
ARCHS="i386 mips arm riscv"

cleanup_tmpdir() {
	cd
	rm -r $TMPDIR
}

create_results_dirs() {
	mkdir -p $BASE/coreboot/dbd
}

call_debbindiff() {
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	set +e
	( timeout $TIMEOUT schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-debbindiff \
		debbindiff -- \
			--html $TMPDIR/$1.html \
			$TMPDIR/b1/$1/coreboot.rom \
			$TMPDIR/b2/$1/coreboot.rom 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG # print dbd output
	rm -f $TMPLOG
	case $RESULT in
		0)	echo "$(date -u) - $1/coreboot.rom is reproducible, yay!"
			;;
		1)
			echo "$(date -u) - $DBDVERSION found issues, please investigate $1/coreboot.rom"
			;;
		2)
			echo "$(date -u) - $DBDVERSION had trouble comparing the two builds. Please investigate $1/coreboot.rom"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				echo "$(date -u) - $DBDVERSION produced no output for $1/coreboot.rom and was killed after running into timeout after ${TIMEOUT}..."
			else
				local msg="$DBDVERSION was killed after running into timeout after $TIMEOUT"
				msg="$msg, but there is still $TMPDIR/$1.html"
			fi
			echo $msg
			;;
		*)
			echo "$(date -u) - Something weird happened when running $DBDVERSION on $1/coreboot.rom (which exited with $RESULT) and I don't know how to handle it"
			;;
	esac
}

#
# main
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_tmpdir INT TERM EXIT
cd $TMPDIR

DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
mkdir b1 b2

echo "============================================================================="
echo "$(date -u) - Cloning the coreboot git repository with submodules now."
echo "============================================================================="
git clone --recursive http://review.coreboot.org/p/coreboot.git
cd coreboot
# still required because coreboot moved submodules and to take care of old git versions
git submodule update --init --checkout 3rdparty/blobs
COREBOOT="$(git log -1)"
COREBOOT_VERSION=$(git describe)

echo "============================================================================="
echo "$(date -u) - Building cross compilers for ${ARCHS} now."
echo "============================================================================="
for ARCH in ${ARCHS} ; do 
	nice ionice -c 3 make crossgcc-$ARCH || true # don't fail the full job just because some targets fail
done

echo "============================================================================="
echo "$(date -u) - Building coreboot ${COREBOOT_VERSION} images now - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
# prevent failing using more than one CPU
sed -i 's#MAKE=$i#MAKE=make#' util/abuild/abuild
# use all cores for first build
NUM_CPU=$(cat /proc/cpuinfo |grep '^processor'|wc -l)
sed -i "s#cpus=1#cpus=$NUM_CPU#" util/abuild/abuild
sed -i 's#USE_XARGS=1#USE_XARGS=0#g' util/abuild/abuild
# actually build everything
nice ionice -c 3 \
	bash util/abuild/abuild || true # don't fail the full job just because some targets fail

cd coreboot-builds
for i in * ; do
	mkdir $TMPDIR/b1/$i
	if [ -f $i/coreboot.rom ] ; then
		cp -p $i/coreboot.rom $TMPDIR/b1/$i/
	fi
done
cd ..
rm coreboot-builds -rf

echo "============================================================================="
echo "$(date -u) - Building coreboot images now - second build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="fr_CH.UTF-8"
export LC_ALL="fr_CH.UTF-8"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
umask 0002
# use allmost all cores for second build
NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
sed -i "s#cpus=$NUM_CPU#cpus=$NEW_NUM_CPU#" util/abuild/abuild
nice ionice -c 3 \
	linux64 --uname-2.6 \
	bash util/abuild/abuild || true # don't fail the full job just because some targets fail

# reset environment to default values again
export LANG="en_GB.UTF-8"
unset LC_ALL
export TZ="/usr/share/zoneinfo/UTC"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
umask 0022

cd coreboot-builds
for i in * ; do
	if [ -f $i/coreboot.rom ] ; then
		mkdir $TMPDIR/b2/$i
		cp -p $i/coreboot.rom $TMPDIR/b2/$i/
	fi
done
cd ..
rm coreboot-builds -r
cd ..

TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DBDVERSION on coreboot images now"
echo "============================================================================="
# and creating the webpage while we're at it
PAGE=$PWD/coreboot/coreboot.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>coreboot</title>
    <link rel='stylesheet' id='twentyfourteen-style-css'  href='landing_style.css?ver=4.0' type='text/css' media='all' />
  </head>
  <body>
    <div class="content">
      <div class="page-content">
        <p>&nbsp;</p>
        <p><center><img src="coreboot.png" width="300" class="alignnone size-medium wp-image-6" alt="coreboot" height="231" /><br />
        <blockquote>
	  <br />
          <strong>coreboot&trade;</strong>: fast, flexible <em>and reproducible</em> Open Source firmware?
        </blockquote>
       </center></p>
EOF
write_page "       <h1>Reproducible Coreboot</h1>"
write_page "       <p><em>Reproducible builds</em> enable anyone to reproduce bit by bit identical binary packages from a given source, si that anyone can verify that a given binary derived from the source it was said to be derived. There is a lot more information about <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds on the Debian wiki</a> and on <a href=\"https://reproducible.debian.net\">https://reproducible.debian.net</a>.<br />"
write_page "        <em>Reproducible Coreboot</em> is an effort to apply this to coreboot. Thus each coreboot.rom is build twice, with a few varitations added and then those two ROMs are compared using <a href=\"https://tracker.debian.org/debbindiff\">debbindiff</a>. Please note that more variations are to be expected in the wild.t</p>"
write_page "       <p>This set up to test the <code>master</code> branch of <a href=\"https://review.coreboot.org/p/coreboot.git\">coreboot.git</a> monthly, but as this is brand new, currently updates are triggered more often. Patches are very much welcome, the coreboot pages are solely generated by <a href=\"http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/bin/reproducible_coreboot.sh\">reproducible_coreboot.sh</a>.</p>"
write_page "       <p>These tests were last run on $DATE for version ${COREBOOT_VERSION}.</p><p><code>"
echo -n $COREBOOT >> $PAGE
write_page "       </code></p>"
write_explaination_table coreboot
write_page "       <ul>"
BAD_ROMS=0
GOOD_ROMS=0
ALL_ROMS=0
create_results_dirs
cd b1
for i in * ; do
	let ALL_ROMS+=1
	if [ -f $i/coreboot.rom ] ; then
		call_debbindiff $i
		if [ -f $TMPDIR/$i.html ] ; then
			mv $TMPDIR/$i.html $BASE/coreboot/dbd/$i.html
			write_page "         <li><a href=\"dbd/$i.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $i</a> is unreproducible.</li>"
		else
			write_page "         <li><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $i had no debbindiff output so it's probably reproducible :)</li>"
			let GOOD_ROMS+=1
		fi
	else
		write_page "         <li><img src=\"/userContent/static/weather-storm.png\" alt=\"FTBFS icon\" /> $i <a href=\"${BUILD_URL}console\">failed to build</a> from source.</li>"
		let BAD_ROMS+=1
	fi
done
GOOD_PERCENT=$(echo "scale=1 ; ($GOOD_ROMS*100/$ALL_ROMS)" | bc)
BAD_PERCENT=$(echo "scale=1 ; ($BAD_ROMS*100/$ALL_ROMS)" | bc)
write_page "       </ul><p>$GOOD_ROMS ($GOOD_PERCENT%) out of $ALL_ROMS built coreboot images were reproducible, while $BAD_ROMS ($BAD_PERCENT%) failed to built from source.</p>"
cat >> $PAGE <<- EOF
      </div>
    </div>
EOF
write_page_footer coreboot
cd ..
PAGE=coreboot/coreboot.html
publish_page

# the end
calculate_build_duration
print_out_duration
irc_message "$REPRODUCIBLE_URL/coreboot/ has been updated."

# remove coreboot tree, we don't need it anymore...
rm coreboot -r
cleanup_tmpdir
trap - INT TERM EXIT