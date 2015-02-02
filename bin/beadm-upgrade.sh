#!/bin/bash

### Run package upgrades in a new BE (created by a call to beadm-clone.sh)
### Copyright (C) 2014-2015 by Jim Klimov, License: MIT
### See also: http://wiki.openindiana.org/oi/Advanced+-+Split-root+installation

[ ! -s "`dirname $0`/beadm-clone.sh" ] && \
	echo "FATAL: Can't find beadm-clone.sh" >&2 && \
	exit 1

RES_PKGIPS=-1
RES_PKGSRC=-1
RES_BOOTADM=-1
BREAKOUT=n

trap_exit() {
    RES_EXIT=$1

    echo ""
    beadm list $BENEW
    echo ""

    if [ $RES_EXIT = 0 -a $BREAKOUT = n -a \
	 $RES_PKGIPS -le 0 -a $RES_PKGSRC -le 0 -a $RES_BOOTADM -le 0 ] ; then
        echo "=== SUCCESS, you can now do:  beadm activate $BENEW" >&2
        exit 0
    fi

    [ $RES_EXIT = 0 ] && RES_EXIT=126
    echo "=== FAILED, the upgrade was not completed successfully" \
    	    "or found no new updates; you can remove the new BE with:" \
    	    " beadm destroy -Ffsv $BENEW " >&2
    exit $RES_EXIT
}

trap "BREAKOUT=y; exit 127;" 1 2 3 15
trap 'trap_exit $?' 0

# Support package upgrades in an existing (alt)root
if [ -n "$BENEW" ] && beadm list "$BENEW" > /dev/null ; then
    echo "INFO: It seems that BENEW='$BENEW' already exists; ensuring it is mounted..."
    _BEADM_CLONE_INFORM=no _BEADM_CLONE=no . "`dirname $0`/beadm-clone.sh"
    RES=$?

    if [ -n "$BENEW_MNT" -a -n "$BENEW_DS" -a -n "$BENEW" -a $RES = 0 ]; then
	_MPT="`/bin/df -Fzfs -k "$BENEW_MNT" | awk '{print $1}' | grep "$BENEW_DS"`"
	if [ x"$_MPT" != x"$BENEW_DS" -o -z "$_MPT" ]; then
		beadm mount "$BENEW" "$BENEW_MNT" || exit
		_MPT="`/bin/df -Fzfs -k "$BENEW_MNT" | awk '{print $1}' | grep "$BENEW_DS"`"
		[ x"$_MPT" != x"$BENEW_DS" -o -z "$_MPT" ] && \
			echo "FATAL: Can't mount $BENEW at $BENEW_MNT"
	fi
    else
	[ "$RES" = 0 ] && RES=125
    fi
else
    . "`dirname $0`/beadm-clone.sh"
    RES=$?
fi
[ $RES != 0 -o x"$BENEW" = x ] && \
	echo "FATAL: Failed to use beadm-clone.sh" >&2 && \
	exit 2

beadm list "$BENEW"
[ $? != 0 ] && \
	echo "FATAL: Failed to locate the BE '$BENEW'" >&2 && \
	exit 3


echo ""
echo "======================== `date` ==================="
echo "=== Beginning package upgrades in the '$BENEW' image mounted at '$BENEW_MNT'..."

### Note that IPS pkg command does not work under a simple chroot
if [ -x /usr/bin/pkg ]; then
    echo "=== Run IPS pkg upgrade..."
    /usr/bin/pkg -R "$BENEW_MNT" image-update --accept --licenses --deny-new-be --no-backup-be
    RES_PKGIPS=$?
    TS="`date -u "+%Y%m%dZ%H%M%S"`" && \
	zfs snapshot -r "$RPOOL_SHARED@postupgrade_pkgips-$TS" && \
	zfs snapshot -r "$BENEW_DS@postupgrade_pkgips-$TS"
fi

if [ -x "$BENEW_MNT"/opt/local/bin/pkgin ]; then
    echo "=== Run PKGSRC upgrade..."
    yes | chroot "$BENEW_MNT" /opt/local/bin/pkgin full-upgrade
    RES_PKGSRC=$?
    TS="`date -u "+%Y%m%dZ%H%M%S"`" && \
	zfs snapshot -r "$RPOOL_SHARED@postupgrade_pkgsrc-$TS" && \
	zfs snapshot -r "$BENEW_DS@postupgrade_pkgsrc-$TS"
fi

echo "=== Reconfiguring boot-archive in new BE..."
touch "$BENEW_MNT/reconfigure" && \
bootadm update-archive -R "$BENEW_MNT"
RES_BOOTADM=$?

echo "=== Unmounting $BENEW ($BENEW_MNT)..."
beadm umount "$BENEW_MNT"

echo "=== Done: IPS=$RES_PKGIPS PKGSRC=$RES_PKGSRC BOOTADM=$RES_BOOTADM"
echo "=== If upgrade was acceptable and successful:"
echo ":; beadm activate '$BENEW'"
echo "=== If you change your mind or if it failed:"
echo ":; beadm destroy -Ffsv '$BENEW'"
