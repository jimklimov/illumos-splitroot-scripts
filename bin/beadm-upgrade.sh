#!/bin/bash

### Run package upgrades in a new BE (created by a call to beadm-clone.sh)
### Copyright (C) 2014-2015 by Jim Klimov
### See also: http://wiki.openindiana.org/oi/Advanced+-+Split-root+installation

[ ! -s "`dirname $0`/beadm-clone.sh" ] && \
	echo "FATAL: Can't find beadm-clone.sh" >&2 && \
	exit 1

RES_PKGIPS=-1
RES_PKGSRC=-1
RES_BOOTADM=-1
BREAKOUT=n

trap "BREAKOUT=y; exit 127;" 1 2 3 15
trap 'RES_EXIT=$?; beadm list $BENEW; [ $RES_EXIT = 0 -a $RES_PKGIPS = 0 -a $RES_PKGSRC = 0 -a $RES_BOOTADM = 0 -a $BREAKOUT = n ] && { echo "=== SUCCESS, you can now do: beadm activate $BENEW" >&2; exit 0; } || { [ $RES_EXIT = 0 ] && RES_EXIT=126; echo "=== FAILED, the upgrade was not completed successfully or found no new updates; you can remove the new BE with: beadm destroy -Ffsv $BENEW " >&2; exit $RES_EXIT; }' 0

. "`dirname $0`/beadm-clone.sh"
[ $? != 0 -o x"$BENEW" = x ] && \
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
else
    RES_PKGIPS=0
fi

if [ -x "$BENEW_MNT"/opt/local/bin/pkgin ]; then
    echo "=== Run PKGSRC upgrade..."
    yes | chroot "$BENEW_MNT" /opt/local/bin/pkgin full-upgrade
    RES_PKGSRC=$?
    TS="`date -u "+%Y%m%dZ%H%M%S"`" && \
	zfs snapshot -r "$RPOOL_SHARED@postupgrade_pkgsrc-$TS" && \
	zfs snapshot -r "$BENEW_DS@postupgrade_pkgsrc-$TS"
else
    RES_PKGSRC=0
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
