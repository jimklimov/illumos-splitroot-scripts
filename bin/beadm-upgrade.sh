#!/bin/bash

### Run package upgrades in a new BE (created by a call to beadm-clone.sh)
### Copyright (C) 2014-2015 by Jim Klimov, License: CDDL
### See also: http://wiki.openindiana.org/oi/Advanced+-+Split-root+installation

PATH=/usr/gnu/bin:/usr/sfw/bin:/opt/gnu/bin:/opt/sfw/bin:/opt/omni/bin:/bin:/sbin:/usr/sbin:/usr/bin:$PATH
LANG=C
LC_ALL=C
export LANG LC_ALL PATH

[ ! -s "`dirname $0`/beadm-clone.sh" ] && \
	echo "FATAL: Can't find beadm-clone.sh" >&2 && \
	exit 1

RES_PKGIPS=-1
RES_PKGSRC=-1
RES_BOOTADM=-1
RES_FIREFLY=-1
BREAKOUT=n

trap_exit_upgrade() {
    RES_EXIT=$1

    echo ""
    beadm list $BENEW
    /bin/df -k | awk '( $NF ~ "^'"$BENEW_MNT"'($|/)" ) { print $0 }'
    echo ""

    if [ $RES_EXIT = 0 -a $BREAKOUT = n ] && \
       [ $RES_PKGIPS -le 0 -o $RES_PKGIPS = 4 ] && \
       [ $RES_PKGSRC -le 0 -a $RES_BOOTADM -le 0 ] \
    ; then
        do_clone_umount
        [ $? = 0 -o $? = 185 ] && \
        do_normalize_mountattrs
    fi

    echo "=== Done: PKGIPS=$RES_PKGIPS PKGSRC=$RES_PKGSRC BOOTADM=$RES_BOOTADM FIREFLY=$RES_FIREFLY"

    if [ $RES_EXIT = 0 -a $BREAKOUT = n -a \
        $RES_PKGSRC -le 0 -a $RES_BOOTADM -le 0 ] \
    ; then
        ### We do not care much about RES_FIREFLY now, which could fail
        ### for many reasons such as lack of the downloaded ISO image
        if [ $RES_PKGIPS -le 0 ]; then
            echo "=== SUCCESS, you can now do:"
            echo "  beadm activate '$BENEW'    && init 6"
            exit 0
        fi
        if [ $RES_PKGIPS = 4 ]; then
            echo "=== NOT FAILED (but may have had nothing to upgrade though), you can now do:"
            echo "  beadm activate '$BENEW'    && init 6"
            echo "... or if you change your mind:"
            echo "  beadm destroy -Ffsv '$BENEW'"
            exit 0
        fi
    fi >&2

    [ $RES_EXIT = 0 ] && RES_EXIT=126
    echo "=== FAILED, the upgrade was not completed successfully" \
        "or maybe found no new updates; you can remove the new BE with:" >&2
    echo "	beadm destroy -Ffsv '$BENEW' " >&2
    exit $RES_EXIT
}

trap_exit_mount() {
    RES_EXIT=$1

    echo ""
    beadm list $BENEW
    /bin/df -k | awk '( $NF ~ "^'"$BENEW_MNT"'($|/)" ) { print $0 }'
    echo ""

    if [ $RES_EXIT = 0 -a $BREAKOUT = n ]; then
        echo "=== SUCCESS, (un)mounting operations completed for BE '$BENEW' at '$BENEW_MPT'" >&2
        exit 0
    fi

    [ $RES_EXIT = 0 ] && RES_EXIT=126
    echo "=== FAILED (un)mounting operations for BE '$BENEW' at '$BENEW_MPT'" >&2
    exit $RES_EXIT
}

do_ensure_configs() {
    RES=0
    if [ -n "$BENEW" ] && beadm list "$BENEW" > /dev/null ; then
	echo "INFO: It seems that BENEW='$BENEW' already exists; ensuring it is mounted..."
	_BEADM_CLONE_INFORM=no _BEADM_CLONE=no . "`dirname $0`/beadm-clone.sh"
	RES=$?
    else
	. "`dirname $0`/beadm-clone.sh"
	RES=$?
    fi
    [ $RES != 0 -o x"$BENEW" = x ] && \
	echo "FATAL: Failed to use beadm-clone.sh" >&2 && \
	exit 2

    return 0
}

do_clone_mount() {
    # This routine ensures that variables have been set and altroot is mounted
    # Note that we also support package upgrades in an existing (alt)root

    [ -z "$BENEW" -o -z "$BENEW_MNT" -o -z "$BENEW_DS" -o -z "$RPOOL_SHARED" ] && \
        echo "ERROR: do_clone_mount(): BENEW or BENEW_MNT or BENEW_DS or RPOOL_SHARED is not set" && \
        return 1

    echo "INFO: Unmounting any previous traces (if any - may fail), just in case"
    do_clone_umount

    if [ -n "$BENEW_MNT" -a -n "$BENEW_DS" -a -n "$BENEW" ]; then
	_MPT="`/bin/df -Fzfs -k "$BENEW_MNT" | awk '{print $1}' | grep "$BENEW_DS"`"
	if [ x"$_MPT" != x"$BENEW_DS" -o -z "$_MPT" ]; then
	    beadm mount "$BENEW" "$BENEW_MNT" || exit
	    _MPT="`/bin/df -Fzfs -k "$BENEW_MNT" | awk '{print $1}' | grep "$BENEW_DS"`"
	    [ x"$_MPT" != x"$BENEW_DS" -o -z "$_MPT" ] && \
		echo "FATAL: Can't mount $BENEW at $BENEW_MNT" && \
		exit 3
	fi
    else
	echo "FATAL: Configuration not determined" >&2
	exit 2
    fi

    beadm list "$BENEW"
    [ $? != 0 ] && \
	echo "FATAL: Failed to locate the BE '$BENEW'" >&2 && \
	exit 3

    _MPT="`/bin/df -Fzfs -k "$BENEW_MNT" | awk '($1 == "'"$BENEW_DS"'") {print $1}'`"
    [ x"$_MPT" != x"$BENEW_DS" -o -z "$_MPT" ] && \
	echo "FATAL: Could not mount $BENEW at $BENEW_MNT"

    # Now, ensure that shared sub-datasets (if any) are also lofs-mounted
    # /proc is needed for pkgsrc dependencies (some getexecname() fails otherwise)
    # /dev/urandom is needed for pkgips python scripts
    for _SMT in /tmp /proc /dev /devices \
	`/bin/df -k | awk '( $1 ~ "^'"$RPOOL_SHARED"'" ) { print $NF }'` \
    ; do
	echo "===== lofs-mount '$_SMT' at '$BENEW_MNT$_SMT'"
	mount -F lofs -o rw "$_SMT" "$BENEW_MNT$_SMT"
    done

    return 0
}

do_clone_umount() {
    # This routine ensures altroot is unmounted

    [ -z "$BENEW" -o -z "$BENEW_MNT" ] && \
        echo "ERROR: do_clone_umount(): BENEW or BENEW_MNT is not set" && \
        return 1

    echo "=== Unmounting BE $BENEW under '$BENEW_MNT'..."

    /bin/df -k -F lofs | \
	awk '( $NF ~ "^'"$BENEW_MNT"'/.*" ) { print $1" "$NF }' | \
	sort -r | while read _LFS _LMT; do
	    echo "===== unmounting '$_LFS' bound over '$_LMT'..."
	    umount "$_LMT"
	done

    echo "===== beadm-unmounting $BENEW ($BENEW_MNT)..."
    beadm umount "$BENEW_MNT" || \
    beadm umount "$BENEW"
}

do_normalize_mountattrs() {
    [ -z "$BENEW_DS" ] && \
        echo "ERROR: do_normalize_mountattrs() BENEW_DS is not set" && \
        return 1

    echo "=== Normalizing canmount and mountpoint attributes..."

    echo "===== Enforcing for $BENEW_DS"
    zfs set canmount=noauto "$BENEW_DS" && \
    zfs set mountpoint=/ "$BENEW_DS" && \
    zfs list -t filesystem -Honame -r "$BENEW_DS" | grep "$BENEW_DS/" | sort | \
    while read Z; do
	echo "===== Inheriting for $Z" && \
	zfs set canmount=noauto "$Z" && \
	zfs inherit mountpoint "$Z"
    done
}

do_upgrade_pkgips() {
    ### Note that IPS pkg command does not work under a simple chroot
    ### but has proper altroot support instead
    if [ -x /usr/bin/pkg ]; then
	echo "=== Run IPS pkg upgrade (refresh package list, update pkg itself, update others)..."

        echo "===== Querying the configured IPS publishers for '$BENEW' in '$BENEW_MNT'"
	/usr/bin/pkg -R "$BENEW_MNT" publisher

	{ echo "===== Refreshing IPS package list"
          /usr/bin/pkg -R "$BENEW_MNT" refresh
          RES_PKGIPS=$?; [ "$RES_PKGIPS" = 0 ] ; } && \
	{ echo "===== Updating PKG software itself"
          ### This clause should fail if no 'pkg' updates were available, or if a
          ### chrooted upgrade attempt with the new 'pkg' failed - both ways fall
          ### through to altroot upgrade attempt
          /usr/bin/pkg -R "$BENEW_MNT" update --no-refresh --accept --deny-new-be --no-backup-be pkg
          RES_PKGIPS=$?; [ "$RES_PKGIPS" = 0 ] || [ "$RES_PKGIPS" = 4 ] ; } && \
        { echo "===== Updating the image with new PKG software via chroot with a special variable"
          PKG_LIVE_ROOT=/// chroot "$BENEW_MNT" /usr/bin/pkg -R / image-update --no-refresh --accept --deny-new-be --no-backup-be
          RES_PKGIPS=$?; [ "$RES_PKGIPS" = 0 ] || [ "$RES_PKGIPS" = 4 ] ; } || \
        { echo "===== Updating the image with new PKG software via chroot"
          chroot "$BENEW_MNT" /usr/bin/pkg -R / image-update --no-refresh --accept --deny-new-be --no-backup-be
          RES_PKGIPS=$?; [ "$RES_PKGIPS" = 0 ] || [ "$RES_PKGIPS" = 4 ] ; } || \
	{ echo "===== Updating the image with old PKG software via altroot"
          /usr/bin/pkg -R "$BENEW_MNT" image-update --no-refresh --accept --deny-new-be --no-backup-be
          RES_PKGIPS=$?; [ "$RES_PKGIPS" = 0 ] || [ "$RES_PKGIPS" = 4 ] ; } || \
	{ echo "===== Updating the image with old PKG software via altroot and allowed refresh"
          /usr/bin/pkg -R "$BENEW_MNT" image-update --accept --deny-new-be --no-backup-be
          RES_PKGIPS=$?; }

        if [ "$RES_PKGIPS" = 0 -o "$RES_PKGIPS" = 4 ]; then
                # Had success or nothing to do in the GZ, try LZ's now
                chroot "$BENEW_MNT" /usr/sbin/zoneadm list -cp | \
                awk -F: '( $6 == "ipkg" && $2 != "global" ) { print $4}' | \
                while read ZR; do
                        if /bin/df -k "/$BENEW_MNT/$ZR/root" | \
                            grep "ROOT/zbe" >/dev/null ; then
                                echo ""
                                { echo "===== Updating the image with new PKG software via chroot with a special variable in a local zone: $ZR"
                                  PKG_LIVE_ROOT=/// chroot "$BENEW_MNT" /usr/bin/pkg -R /$ZR/root image-update --no-refresh --accept --deny-new-be --no-backup-be
                                  RES_PKGIPS_Z=$?; [ "$RES_PKGIPS_Z" = 0 ] || [ "$RES_PKGIPS_Z" = 4 ] ; } || \
                                { echo "===== Updating the image with old PKG software via altroot in a local zone: $ZR"
                                  /usr/bin/pkg -R "$BENEW_MNT/$ZR/root" image-update --no-refresh --accept --deny-new-be --no-backup-be
                                  RES_PKGIPS_Z=$?; }
                                RES_PKGIPS_Z=$?
                                case "$RES_PKGIPS_Z" in
                                        0) [ "$RES_PKGIPS" = 0 -o \
                                             "$RES_PKGIPS" = 4 ] && \
                                                RES_PKGIPS=0;; # good news
                                        4) ;; # ignore no zone news
                                        *) RES_PKGIPS="$RES_PKGIPS_Z" ;; # bad
                                esac
                        fi
                done
        fi

        echo ""
        echo "===== Querying the version of osnet-incorporation for '$BENEW' in '$BENEW_MNT' (FYI)"
        /usr/bin/pkg -R "$BENEW_MNT" info osnet-incorporation

	TS="`date -u "+%Y%m%dZ%H%M%S"`" && \
            echo "===== Taking snapshots @postupgrade_pkgips-$TS ..." && \
	    zfs snapshot -r "$RPOOL_SHARED@postupgrade_pkgips-$TS" && \
	    zfs snapshot -r "$BENEW_DS@postupgrade_pkgips-$TS" && \
            chroot "$BENEW_MNT" /usr/sbin/zoneadm list -cp | \
            awk -F: '( $6 == "ipkg" && $2 != "global" ) { print $4}' | \
            while read ZR; do
                ### A zoneroot dataset contains a ZBE whose snapshot we want,
                ### but also it can contain split-off userdata datasets which
                ### we can also want. A dirty solution for now is to snapshot
                ### zoneroot with all children (slight overkill for zbe-NN).
                ZRDS="`/bin/df -k "/$BENEW_MNT/$ZR/root" | grep "ROOT/zbe" | awk '{print $1}' | sed 's,/ROOT/zbs.*$,,'`"
                [ $? = 0 ] && [ -n "$ZRDS" ] && \
                    zfs snapshot -r "$ZRDS@postupgrade_pkgips-$TS"
            done
    fi
}

do_upgrade_pkgsrc() {
        # TODO: PKGSRC upgrades in local zones (new ZBEs) as well
        # (do not limit to ipkg zones however ;) )
    if [ -x "$BENEW_MNT"/opt/local/bin/pkgin ]; then
	echo "=== Run PKGSRC upgrade..."
	chroot "$BENEW_MNT" /opt/local/bin/pkgin update
	RES_PKGSRC=$?
	yes | chroot "$BENEW_MNT" /opt/local/bin/pkgin full-upgrade
	RES_PKGSRC=$?
#	echo "===== Run PKGSRC orphan autoremoval..."
#	chroot "$BENEW_MNT" /opt/local/bin/pkgin autoremove || RES_PKGSRC=$?
	TS="`date -u "+%Y%m%dZ%H%M%S"`" && \
            echo "===== Taking snapshots @postupgrade_pkgsrc-$TS ..." && \
	    zfs snapshot -r "$RPOOL_SHARED@postupgrade_pkgsrc-$TS" && \
	    zfs snapshot -r "$BENEW_DS@postupgrade_pkgsrc-$TS"
    fi
}

do_reconfig() {
    echo "=== Reconfiguring boot-archive in new BE..."
    touch "$BENEW_MNT/reconfigure" && \
	bootadm update-archive -R "$BENEW_MNT"
    RES_BOOTADM=$?
}

do_firefly() {
    [ -x "`dirname "$0"`/beadm-firefly-update.sh" ] && \
    if [ $RES_PKGIPS -le 0 -a $RES_PKGSRC -le 0 -a $RES_BOOTADM -le 0 ] || \
       [ -n "`set | egrep '^FIREFLY_[A-Za-z0-9_]*='`" ] \
    ; then
        [ -z "$FIREFLY_CONTAINER_TGT" ] && \
                FIREFLY_CONTAINER_TGT=integrated
        export FIREFLY_CONTAINER_TGT BENEW BENEW_MPT CURRENT_BE CURRENT_RPOOL RPOOL RPOOL_ROOT RPOOLALT
        echo "=== Will try to upgrade the Firefly Failsafe image (if available)" \
                "in the new BE, since at least some package updates succeeded there..."
        "`dirname "$0"`/beadm-firefly-update.sh"
        RES_FIREFLY=$?
    fi
}

do_upgrade() {
    do_ensure_configs || exit
    do_clone_mount || exit

    echo ""
    echo ""
    echo "======================== `date` ==================="
    echo "=== Beginning package upgrades in the '$BENEW' image mounted at '$BENEW_MNT'..."

    echo "===== Querying the current HTTP proxy settings (if any) as may impact PKG downloads"
    set | egrep '^(http|ftp)s?_proxy='

    echo ""
    do_upgrade_pkgips

    echo ""
    do_upgrade_pkgsrc

    echo ""
    do_reconfig

    echo ""
    do_firefly

    # Unmounting and reporting is done as part of trapped exit()

}

trap "BREAKOUT=y; exit 127;" 1 2 3 15

case "`basename $0`" in
    *upgrade*)
		trap 'trap_exit_upgrade $?' 0
		do_upgrade
                ;;
    *umount*)	[ -z "$BENEW" ] && \
		    echo "FATAL: BENEW not defined, nothing to unmount" && \
		    exit 1
		trap 'trap_exit_mount $?' 0
		do_ensure_configs
		do_clone_umount
		do_normalize_mountattrs
                ;;
    *mount*)	[ -z "$BENEW" ] && \
		    echo "FATAL: BENEW not defined, nothing to mount" && \
		    exit 1
		trap 'trap_exit_mount $?' 0
		do_ensure_configs || exit
		do_clone_mount
                ;;
    *)		echo "FATAL: Command not determined: $@"
                exit 1
                ;;
esac
