#!/bin/bash

### Automate creation of a new BE based on a specified old one or the currently
### running one, including replication of custom ZFS attributes (compression).
### Parameters are passed from ENV VARS (no CLI so far).
### Assumes BE's hosted in ZFS, minimal checking enabled for auto-guesses.
### Based on http://wiki.openindiana.org/oi/Advanced+-+Split-root+installation
### Copyright (C) 2013-2014 by Jim Klimov, License: CDDL

# First of all, just set missing environment variables
CURRENT_BE="`beadm list -H | while IFS=";" read BENAME BEGUID BEACT BEMPT BESPACE BEPOLICY BESTAMP; do case "$BEACT" in *N*) echo $BENAME;; esac; done`"
CURRENT_RPOOL="`grep -w / /etc/mnttab | grep -w zfs | sed 's,^\([^\/]*\)/.*,\1,'`" || \
    CURRENT_RPOOL=""

[ x"$BEOLD" = x ] && BEOLD="$CURRENT_BE"
[ x"$BENEW" = x ] && \
    BENEW="`echo "$BEOLD" | sed 's/^\([^\-]*\)-.*$/\1/'`-`date -u '+%Y%m%dT%H%M%SZ'`"

[ x"$RPOOL" = x ] && RPOOL="$CURRENT_RPOOL"
[ x"$RPOOL" = x ] && RPOOL="rpool"
[ x"$RPOOL_ROOT" = x ] && RPOOL_ROOT="$RPOOL/ROOT"
[ x"$RPOOL_SHARED" = x ] && RPOOL_SHARED="$RPOOL/SHARED"

[ x"$RPOOLALT" = x ] && \
    RPOOLALT="`zpool get altroot "$RPOOL" | tail -1 | awk '{print $3}'`"
[ x"$RPOOLALT" = x- ] && RPOOLALT=""

[ x"$BEOLD_MPT" = x ] && \
if [ x"$CURRENT_BE" = x"$BEOLD" -a x"$CURRENT_RPOOL" = x"$RPOOL" ]; then
	### For the currently running system
	BEOLD_MPT="/"
else
	BEOLD_MPT="/b"
fi

[ x"$BENEW_MPT" = x ] && BENEW_MPT="/a"

[ x"$BEOLD_DS" = x ] && BEOLD_DS="$RPOOL_ROOT/$BEOLD"
[ x"$BENEW_DS" = x ] && BENEW_DS="$RPOOL_ROOT/$BENEW"
[ x"$BEOLD_MNT" = x ] && BEOLD_MNT="$RPOOLALT$BEOLD_MPT"
[ x"$BENEW_MNT" = x ] && BENEW_MNT="$RPOOLALT$BENEW_MPT" 

[ x"$EXCLUDE_ATTRS" = x ] && \
    EXCLUDE_ATTRS='org.opensolaris.libbe:uuid|canmount|mountpoint'

beadm_clone_attrs() {
    # For a more general solution, not tightly coupled with cloning just
    # a moment ago, consider getting 'zfs origin' of the dataset(s) to
    # find original attrs. Alternately, we might indeed be interested in
    # the BE-to-BE attr replication regardless of ZFS origins.
    echo "=== Trying to replicate ZFS attributes from original to new BE..."
    zfs list -H -o name -r "$BEOLD_DS" | \
    while read Z; do
	S="`echo "$Z" | sed "s,^$BEOLD_DS,,"`"
	echo "===== '$S'"
	zfs get all "$BEOLD_DS$S" | \
		egrep ' (local|received)' | \
		egrep -v "$EXCLUDE_ATTRS" | \
		while read _D A V _T; do \
			echo "$A=$V"; zfs set "$A=$V" "$BENEW_DS$S"; \
		done
    done
    echo "=== Replicated custom ZFS attributes"
}

beadm_clone_whatnext() {
    TS="`date -u "+%Y%m%dT%H%M%SZ"`"

    cat << EOF

=== To upgrade from upstream do:
pkg -R "$BENEW_MNT" image-update --deny-new-be --no-backup-be && \
touch "$BENEW_MNT/reconfigure" && \
bootadm update-archive -R "$BENEW_MNT" && \
beadm umount "$BENEW"

TS="\`date -u "+%Y%m%dT%H%M%SZ"\`"
zfs snapshot -r "$RPOOL_SHARED@postupgrade-\$TS"
zfs snapshot -r "$BENEW_DS@postupgrade-\$TS"

beadm activate "$BENEW"
===

EOF
}

beadm_clone_routine() {
    echo "=== Will clone $BEOLD into $BENEW, ok? Using these settings:"
    set | egrep '^BE|^RPOOL|^EXCL'
    echo "    (Press ENTER or CTRL+C)"
    read LINE

    if [ x"$BEOLD_MPT" != x"/" ]; then
	echo "=== Try to mount $BEOLD at $BEOLD_MNT (not strictly required)..."
	beadm mount "$BEOLD" "$BEOLD_MNT"
    fi

    beadm create -e "$BEOLD" "$BENEW" || exit
    echo "=== Created $BENEW based on $BEOLD"

    beadm_clone_attrs

    beadm mount "$BENEW" "$BENEW_MNT" || exit
    echo "=== Mounted $BENEW at $BENEW_MNT"
    /bin/df -k | grep "$BENEW_DS"

    echo "=== BE clone completed!"
}

beadm_clone_wrapper() {
    if [ x"$_BEADM_CLONE" != "xno" ]; then
	beadm_clone_routine || return
	[ x"$_BEADM_CLONE_INFORM" != "xno" ] && \
	    beadm_clone_whatnext
    fi
    return 0
}

beadm_clone_wrapper
