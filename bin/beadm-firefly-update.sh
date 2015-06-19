#!/bin/bash

### Keep the Firefly failsafe image for illumos up-to-date
### See https://www.blogger.com/comment.g?blogID=3094974977265128267&postID=6716498883875252619
### and https://github.com/jimklimov/illumos-splitroot-scripts
### Script Copyright (C) 2014-2015 by Jim Klimov
### Firefly Copyright (C) by Alex Eremin aka "alhazred"

### NOTE: This is an experimental work in progress. This script does function,
### but it is currently configured in a user-unfriendly manner of setting some
### environment variables that may be subject to change over time.
### It is integrated with "illumos-splitroot-scripts" (if BENEW is passed by
### the caller) as a way to produce an updated Firefly tailored to the newly
### upgraded OS version. Otherwise this script is quite autonomous by itself.
###
### This script helps both storage of the Firefly archive image "integrated"
### with the current BE (along with its version of the "unix" binary) so that
### booting into the recovery mode is just a matter of attaching another
### "module$" in the boot-loader, as well as as a "standalone" recovery BE.
### The former saves some hassle with extra BE's (which may cause scalability
### problems), while the latter does not require to always upgrade the failsafe
### image as you upgrade the kernel bits (many pieces must be in sync) and also
### dormant little-used filesystems (dedicated to failsafe) tend to suffer less
### from random system events that might impact a production RW root dataset.

die() {
        [ $# != 0 ] && echo "" >&2
        while [ $# != 0 ]; do echo "$1"; shift; done >&2
        echo "" >&2
        echo "FATAL ERROR occurred, bailing out (see details above," \
                "please clean up accordingly after inspecting the wreckage)" >&2
        exit 1
}

uuid() {
        # Generate a pseudo UUID in BASH.
        # Adapted from https://gist.github.com/markusfisch/6110640
        local N B C='89ab'
        for (( N=0; N < 16; ++N )); do
                B=$(( $RANDOM%256 ))
                case "$N" in
                        6) printf '4%x' $(( B%16 )) ;;
                        8) printf '%c%x' ${C:$RANDOM%${#C}:1} $(( B%16 )) ;;
                        3 | 5 | 7 | 9)
                           printf '%02x-' $B ;;
                        *) printf '%02x' $B ;;
                esac
        done
        echo
}

initialize_envvars_beadm_firefly() {
        isainfo | grep amd64 \
                || die "ERROR: amd64 support not detected in the current OS" \
                        "Known Firefly Failsafe versions require that," \
                        "so running this script is irrelevant."

        ### The current BE name, will be used to pick up updated files
        ### to refresh the FF image, and to partially name the new FF BE
        CURRENT_BE="`beadm list -H | while IFS=";" read BENAME BEGUID BEACT BEMPT BESPACE BEPOLICY BESTAMP; do case "$BEACT" in *N*) echo "$BENAME";; esac; done`" \
                || die "No CURRENT_BE found"

        ### How to refer to the rpool we are mangling (current or different)?
        CURRENT_RPOOL="`grep -w / /etc/mnttab | grep -w zfs | sed 's,^\([^\/]*\)/.*,\1,'`" \
                || CURRENT_RPOOL=""
        [ x"$RPOOL" = x ] && RPOOL="$CURRENT_RPOOL"
        [ x"$RPOOL" = x ] && RPOOL="rpool"
        [ x"$RPOOL_ROOT" = x ] && RPOOL_ROOT="$RPOOL/ROOT"

        [ x"$RPOOLALT" = x ] && \
                RPOOLALT="`zpool get altroot "$RPOOL" | tail -1 | awk '{print $3}'`"
        [ x"$RPOOLALT" = x- ] && RPOOLALT=""

        ### Support integration with other illumos-splitroot project scripts
        export BENEW BENEW_MPT
        if [ -n "$BENEW" ] && [ "$BENEW" != "$CURRENT_BE" ]; then
                ### For this script, an alternate BE must already be installed
                echo "INFO: Validating alternate BENEW='$BENEW'..."
                beadm list "$BENEW" || die

                ### See if it is already mounted?
                BENEW_MPT_CUR="`beadm list -H "$BENEW" | awk -F';' '{print $4}'`" \
                || BENEW_MPT_CUR=""

                ### Rule out current BE
                [ "$BENEW_MPT_CUR" = "/" ] && \
                        BENEW="$CURRENT_BE" && \
                        BENEW_MPT="" \
                || if [ -n "$BENEW_MPT" -a \
                      ! -d "$BENEW_MPT/platform/i86pc/amd64" ] \
                   || [ -z "$BENEW_MPT" ] \
                ; then
                        if [ -n "$BENEW_MPT_CUR" ] && \
                           [ x"$BENEW_MPT_CUR" != x"-" ] \
                        ; then
                                echo "BENEW is already mounted at '$BENEW_MPT_CUR', using that..."
                                BENEW_MPT="$BENEW_MPT_CUR"
                        else
                                [ -z "$BENEW_MPT" ] && \
                                        BENEW_MPT="/tmp/ff-BENEW-$$.mpt" && \
                                        mkdir -p "$BENEW_MPT" \
                                        || BENEW_MPT="" # Grab defaults below

                                ### Script sets all the variables if available
                                [ -s "`dirname $0`/beadm-clone.sh" ] && \
                                        _BEADM_CLONE_INFORM=no _BEADM_CLONE=no . "`dirname $0`/beadm-clone.sh"

                                if [ -x "`dirname "$0"`/beadm-mount.sh" ] ; then
                                        echo "Using '`dirname "$0"`/beadm-mount.sh' to ensure that BENEW='$BENEW' is mounted"
                                        "`dirname "$0"`/beadm-mount.sh" || die
                                else
                                        echo "Got a BENEW='$BENEW' with invalid BENEW_MPT='$BENEW_MPT' and got no 'beadm-mount.sh' - trying common 'beadm mount'"
                                        ### Even with split-root installations, system
                                        ### stuff is in (or childed under) the rootfs,
                                        ### so a common "beadm mount" should suffice.
                                        beadm mount "$BENEW" "$BENEW_MPT" || die
                                fi
                        fi
                fi
                if [ -n "$BENEW_MPT" ] && \
                   [ -d "$BENEW_MPT/platform/i86pc/amd64" ] \
                ; then
                        echo "Got valid BENEW='$BENEW' and BENEW_MPT='$BENEW_MPT' for ABE-based failsafe installation"
                        case "$BENEW_MPT" in
                                /tmp/ff-*) ;;
                                *) echo "NOTE: This script will not unmount/clean it up when finished!" ;;
                        esac
                else
                        [ -n "$BENEW" ] && \
                        die "Got invalid BENEW='$BENEW' and BENEW_MPT='$BENEW_MPT' and could not mount it (or BE contents are not usable as a bootfs)"

                        # not -n ? then it is current BE
                        BENEW="$CURRENT_BE"
                        BENEW_MPT=""
                fi
        else
                BENEW="$CURRENT_BE"
                BENEW_MPT=""
        fi

        ### Mountpoints. Current BE is assumed to be at root "/" :)
        ### Intentionally untied from specific BE name values.
        [ -z "$FIREFLY_BENEW_MPT" ] && \
                FIREFLY_BENEW_MPT="/tmp/ff-FIREFLY_BENEW-$$.mpt"
        [ -z "$FIREFLY_BEOLD_MPT" ] && \
                FIREFLY_BEOLD_MPT="/tmp/ff-FIREFLY_BEOLD-$$.mpt"
        ### Here we'll lofi-mount the temporary Firefly image (archive) file
        [ -z "$FIREFLY_ARCHIVE_MPT" ] && \
                FIREFLY_ARCHIVE_MPT="/tmp/ff-FIREFLY_ARCHIVE-$$.mpt"
        [ -z "$FIREFLY_ARCHIVE_FILE" ] && \
                FIREFLY_ARCHIVE_FILE="/tmp/ff-FIREFLY_ARCHIVE-$$.img"
        FIREFLY_ARCHIVE_FILE_COMPRESSED="$FIREFLY_ARCHIVE_FILE.gz"
        rm -f "$FIREFLY_ARCHIVE_FILE_COMPRESSED"

        ### Two variables are defaulted below after some detection magic
        ### if not provided by the caller explicitly.
        ### === FIREFLY_CONTAINER_TGT :
        ### Does the user want Firefly as a "standalone" bootable BE,
        ### or "integrated" with OS BE (another bootarchive for same BE)?
        ### Each choice has it pro's and con's, so it is up to the user.
        ### Note that some versions of the illumos bootloader may become
        ### unhappy when there are too many individual BE's around (maybe ~40).
        ### Also user must take care to sync the kernel and boot-archives.
        ### === FIREFLY_CONTAINER_SRC :
        ### A slightly different choice: if a "firefly" archive is available in
        ### the main OS BE, should we look for an ISO and a Firefly BE at all?
        ### The user may provide FIREFLY_CONTAINER_SRCAR for 'integrated' mode.

        ### Envvar not to be provided by user at the moment (use FIREFLY_BEOLD)
        FIREFLY_CONTAINER_SRCBE=""
        ### Can be provided by user for an alternate source file, theoretically
        [ -z "$FIREFLY_CONTAINER_SRCAR" ] && \
                FIREFLY_CONTAINER_SRCAR=""
        case x"$FIREFLY_CONTAINER_SRC" in
                x"standalone") ;; ### may need to create the BE, done later
                x"integrated") ### source - can be extracted from a download
                        if [ -z "$FIREFLY_CONTAINER_SRCAR" ]; then
                                FIREFLY_CONTAINER_SRCAR="$BENEW_MPT/platform/i86pc/amd64/firefly"

                                ### Fallback
                                [ ! -s "$FIREFLY_CONTAINER_SRCAR" ] && \
                                [ -s "/platform/i86pc/amd64/firefly" ] && \
                                [ -n "$BENEW_MPT" ] && \
                                        FIREFLY_CONTAINER_SRCAR="/platform/i86pc/amd64/firefly"
                        fi
                        [ -n "$FIREFLY_CONTAINER_SRCAR" ] && \
                        [ ! -s "$FIREFLY_CONTAINER_SRCAR" ] && \
                                echo "NOTE: FIREFLY_CONTAINER_SRC='$FIREFLY_CONTAINER_SRC' but '$FIREFLY_CONTAINER_SRCAR' file is absent at the moment"
                        ;;
                *)      if [ -n "$FIREFLY_CONTAINER_SRCAR" ] ; then
                                FIREFLY_CONTAINER_SRC="integrated"
                        else
                                FIREFLY_CONTAINER_SRC="auto"
                        fi ;;
        esac

        if [ "$FIREFLY_CONTAINER_SRC" = "standalone" ] || \
           [ "$FIREFLY_CONTAINER_SRC" = "auto" ] \
        ; then
                if [ -z "$FIREFLY_BEOLD" ] ; then
                        ### Pick the latest baseline BE, if any...
                        ### Convert the "firefly_MMYY" pattern back and forth for sorting
                        FIREFLY_CONTAINER_SRCBE="`beadm list | awk 'match($1, /^firefly_[0-9]*$/) {print $1}' | sed 's,^\(firefly_\)\(..\)\(..\)$,\1\3\2,' | sort | tail -1 | sed 's,^\(firefly_\)\(..\)\(..\)$,\1\3\2,'`" 2>/dev/null \
                        || FIREFLY_CONTAINER_SRCBE=""
                        if [ -z "$FIREFLY_CONTAINER_SRCBE" ]; then
                                ### Fall back to any firefly dataset...
                                FIREFLY_CONTAINER_SRCBE="`beadm list | egrep '^firefly_' | awk '{print $1}' | tail -1`" \
                                || FIREFLY_CONTAINER_SRCBE=""
                        fi
                else
                        beadm list "$FIREFLY_BEOLD" > /dev/null 2>&1 && \
                        FIREFLY_CONTAINER_SRCBE="$FIREFLY_BEOLD"
                fi
                if [ -n "$FIREFLY_CONTAINER_SRCBE" ]; then
                        if [ "$FIREFLY_CONTAINER_SRC" = "auto" ]; then
                                FIREFLY_CONTAINER_SRC=standalone
                                echo "NOTE: Since FIREFLY_CONTAINER_SRC was not provided by caller, '$FIREFLY_CONTAINER_SRC' mode was chosen automatically"
                        fi
                        echo "NOTE: Using FIREFLY_CONTAINER_SRCBE='$FIREFLY_CONTAINER_SRCBE' as the assumed source BE dedicated to Firefly Failsafe"
                        FIREFLY_CONTAINER_SRCAR="$FIREFLY_BEOLD_MPT/platform/i86pc/amd64/firefly"
                fi
        fi

        if [ "$FIREFLY_CONTAINER_SRC" = auto ]; then
                [ -s "$BENEW_MPT/platform/i86pc/amd64/firefly" ] && \
                [ -z "$FIREFLY_CONTAINER_SRCAR" ] && \
                        FIREFLY_CONTAINER_SRCAR="$BENEW_MPT/platform/i86pc/amd64/firefly"

                ### Fallback
                [ -s "/platform/i86pc/amd64/firefly" ] && \
                [ -z "$FIREFLY_CONTAINER_SRCAR" ] && \
                [ -n "$BENEW_MPT" ] && \
                        FIREFLY_CONTAINER_SRCAR="/platform/i86pc/amd64/firefly"

                if [ -n "$FIREFLY_CONTAINER_SRCAR" ] ; then
                        FIREFLY_CONTAINER_SRC="integrated"
                else
                        FIREFLY_CONTAINER_SRCAR=""
                        FIREFLY_CONTAINER_SRC="standalone"
                fi
                echo "NOTE: Since FIREFLY_CONTAINER_SRC was not provided by caller, '$FIREFLY_CONTAINER_SRC' mode was chosen automatically"
        fi

        case x"$FIREFLY_CONTAINER_TGT" in
                x"standalone"|x"integrated") ;;
                *)      if [ -s "$BENEW_MPT/platform/i86pc/amd64/firefly" ]; then
                                FIREFLY_CONTAINER_TGT="integrated"
                                echo "NOTE: Since FIREFLY_CONTAINER_TGT was not provided by caller, '$FIREFLY_CONTAINER_TGT' mode was chosen automatically because there is a '$BENEW_MPT/platform/i86pc/amd64/firefly' image"
                        else
                                FIREFLY_CONTAINER_TGT="$FIREFLY_CONTAINER_SRC"
                                echo "NOTE: Since FIREFLY_CONTAINER_TGT was not provided by caller, '$FIREFLY_CONTAINER_TGT' mode was chosen automatically to match FIREFLY_CONTAINER_SRC"
                        fi
                        ;;
        esac

        if [ -n "$FIREFLY_CONTAINER_SRCAR" ] && \
           [ -s "$FIREFLY_CONTAINER_SRCAR" -o \
             -n "$FIREFLY_CONTAINER_SRCBE" ] \
        ; then
                echo "NOTE: We have the source archive we want ($FIREFLY_CONTAINER_SRCAR),"
                echo "either directly or (assumed) as part of an existing dedicated BE ($FIREFLY_CONTAINER_SRCBE)"
                ### Currently FIREFLY_BEOLD doubles as the base (downloaded)
                ### version name used in other parts of the code
                if [ -z "$FIREFLY_BEOLD" ] ; then
                        [ -s "$FIREFLY_CONTAINER_SRCAR" ] && \
                        [ -s "$FIREFLY_CONTAINER_SRCAR.version" ] && \
                                FIREFLY_BEOLD="`head -1 < "$FIREFLY_CONTAINER_SRCAR".version`"

                        [ -z "$FIREFLY_BEOLD" ] && \
                        [ -n "$FIREFLY_CONTAINER_SRCBE" ] && \
                                FIREFLY_BEOLD="`echo "$FIREFLY_CONTAINER_SRCBE" | sed 's,\(firefly_....\).*$,\1,'`"

                        [ -z "$FIREFLY_BEOLD" ] && \
                                FIREFLY_BEOLD="firefly_0000" && \
                                echo "INFO: Falling back to fake downloaded version of the source firefly bootarchive image as '$FIREFLY_BEOLD'" || \
                                echo "INFO: Decided that the source firefly bootarchive image is based on downloaded version '$FIREFLY_BEOLD'"
                fi
        else
                ### Some variables to get the archive are needed...

                ### Pre-requisite currently expected:
                ### Download the Firefly ISO image from its SourceForge project
                ###   http://sourceforge.net/projects/fireflyfailsafe/files/
                ### to your $DOWNLOADDIR
                [ -z "$DOWNLOADDIR" ] && \
                        DOWNLOADDIR="/export/distribs"

                ### The latest (by ctime of the file) baseline Firefly version
                ### taken from ISO filename
                [ -z "$FIREFLY_ISO" ] && \
                        FIREFLY_ISO="`ls --sort=time --time=ctime -1 ${DOWNLOADDIR}/firefly*.iso | head -1`"
                ### Catch wildcards (maybe provided by user) with "ls"
                [ -n "$FIREFLY_ISO" ] && \
                        FIREFLY_ISO="`ls -1 $FIREFLY_ISO | sed 's,//,/,g'`" && \
                        [ -s "$FIREFLY_ISO" ] \
                        || die "No FIREFLY_ISO value or file was found"

                ### TODO[1]: When integrating with common BENEW/BEOLD and
                ### storing "firefly" archives in-place, using a separate
                ### FIREFLY_BEOLD will become optional (flag?)
                [ -z "$FIREFLY_BEOLD" ] && \
                        FIREFLY_BEOLD="`basename "$FIREFLY_ISO" .iso`" \
                        || FIREFLY_BEOLD=""
                ### ... example resulting string:
                #FIREFLY_BEOLD="firefly_0215"
        fi

        ### Used at least in naming of other stuff, so required present
        [ -n "$FIREFLY_BEOLD" ] \
                || die "No FIREFLY_BEOLD value was found"

        ### TODO: Convert usecases of FIREFLY_BEOLD in the code where it means
        ### just a version tag and not so much the BE name, to FIREFLY_BASEVER
        FIREFLY_BASEVER="`echo "$FIREFLY_BEOLD" | sed 's,\(firefly_....\).*$,\1,'`" \
                || FIREFLY_BASEVER="firefly_0000"

        if [ "$FIREFLY_CONTAINER_TGT" = "standalone" ]; then
                ### The new Firefly BE to be updated with files from
                ### FIREFLY_BEOLD
                [ -z "$FIREFLY_BENEW" ] && \
                        FIREFLY_BENEW="${FIREFLY_BEOLD}-${BENEW}"
        else
                ### No BE to create, can (should?) stay empty
                FIREFLY_BENEW=""
        fi

        if [ -z "$GRUB_MENU" ]; then
                [ -z "$RPOOLALT" ] && \
                        ALTROOT_ARG="" || \
                        ALTROOT_ARG="-R $RPOOLALT"
                GRUB_MENU="`LANG=C bootadm list-menu $ALTROOT_ARG | grep 'the location for the active GRUB menu is' | awk '{print $NF}'`"
                [ $? = 0 ] && [ -n "$GRUB_MENU" ] \
                || GRUB_MENU="$RPOOLALT/rpool/boot/grub/menu.lst"
        fi
        ### Stores the last created or existing matching menu entry, if any
        FIREFLY_MENU_TITLE=""

        [ -z "$GZIP_LEVEL" ] && \
                GZIP_LEVEL="-9"
}

beadm_create_raw_begin() {
        ### Creates a BE "$1" with mountpoint in "$2"
        zfs create \
                -o mountpoint="$2" -o canmount=noauto \
                "$RPOOL_ROOT/$1" \
        || die "Could not create a BE dataset '$RPOOL_ROOT/$1'"
}

beadm_create_raw_finish() {
        ### Creates a BE "$1": more work if it is done and populated well
        ### Adds a GRUB comment in $2
        zfs set org.opensolaris.libbe:uuid="`uuid`" "$RPOOL_ROOT/$1" \
        || echo "WARNING: Failed to set (optional) libbe uuid on '$RPOOL_ROOT/$1'"

        if [ -s "$GRUB_MENU" ]; then
                FIREFLY_MENU_TITLE="FireFly FailSafe Recovery $1 $2 amd64"
                if egrep "^bootfs $RPOOL_ROOT/$1\$" \
                    "$GRUB_MENU" > /dev/null; then
                        echo "NOTE: Not adding GRUB menu entry into '$GRUB_MENU':" \
                             "'bootfs $RPOOL_ROOT/$1' line is already present there"
                else
                        echo "Adding GRUB menu entry to use and to clone with 'beadm -e' later into '$GRUB_MENU'"
                        echo "title $FIREFLY_MENU_TITLE
bootfs $RPOOL_ROOT/$1
kernel /platform/i86pc/kernel/amd64/unix
module /platform/i86pc/amd64/firefly
#============ End of LIBBE entry =============" >> "$GRUB_MENU"
                fi
        else
                echo "WARNING: Grub menu file not found at '$GRUB_MENU'"
        fi
        return 0
}

firefly_src_standalone_populate_beold() {
        ### Seed the initial image in a standalone BE, if needed
        ### TODO: See TODO[1] above
        [ "$FIREFLY_CONTAINER_SRC" != "standalone" ] && return 127

        if ! beadm list "$FIREFLY_BEOLD" ; then
                [ -n "$FIREFLY_ISO" ] && [ -s "$FIREFLY_ISO" ] \
                || die "No FIREFLY_ISO value or file was found"

                beadm_create_raw_begin "$FIREFLY_BEOLD" "$FIREFLY_BEOLD_MPT" && \
                zfs mount "$RPOOL_ROOT/$FIREFLY_BEOLD" && \
                ( cd "$RPOOLALT$FIREFLY_BEOLD_MPT" && \
                  7z x "$DOWNLOADDIR/$FIREFLY_BEOLD.iso" ) \
                || die "Could not seed baseline Firefly dataset FIREFLY_BEOLD='$FIREFLY_BEOLD'"
                zfs umount "$RPOOL_ROOT/$FIREFLY_BEOLD"
                beadm_create_raw_finish "$FIREFLY_BEOLD" "(from ISO)"
        fi
        FIREFLY_CONTAINER_SRCAR="$FIREFLY_BEOLD_MNT/platform/i86pc/amd64/firefly"
}

firefly_integrated_addgrub() {
        ### Removal of menu entries associated with a BE is handled by beadm,
        ### but creation - not quite so: only one (first?) is replicated...
        ### Params:
        ### $1 = "src" or "tgt" (for sanity checks)
        ### $2 = bootfs
        ### $3 = kernel
        ### $4 = module (relative to bootfs! exercise for the caller!)
        ### $5 = optional base version of the firefly image (original download)
        [ -z "$1" -o -z "$2" -o -z "$3" -o -z "$4" ] && \
                echo "WARNING: firefly_integrated_addgrub() called with invalid params '$@'" >&2 && \
                return 1        ### Not fatal
        [ "$1" = src ] && [ "$FIREFLY_CONTAINER_SRC" != "integrated" ] && return 127
        [ "$1" = tgt ] && [ "$FIREFLY_CONTAINER_TGT" != "integrated" ] && return 127
        if [ -z "$5" ]; then
                [ -s "$4" ] && \
                [ -s "$4.version" ] && \
                        FFVERSUFFIX="__`head -1 < "$4".version`" \
                || FFVERSUFFIX="__${FIREFLY_BASEVER}"
        else
                FFVERSUFFIX="__$5"
        fi

        if [ -s "$GRUB_MENU" ]; then
                ### Loop through menu file, detect if the entry is present
                ENTRY_PRESENT=no
                _T=""
                _B=""
                _K=""
                _M=""
                while read TAG LINE; do case "$TAG" in
                        [Tt][Ii][Tt][Ll][Ee])
                                [ "$_B" = "$2" -a "$_M" = "$4" ] && \
                                        ENTRY_PRESENT=yes && break
                                _T="$LINE"
                                _B=""; _K=""; _M="" ;;
                        bootfs) _B="$LINE" ;;
                        kernel|kernel\$) _K="$LINE" ;;
                        module|module\$) _M="$LINE" ;;
                        # TODO: Note that in kernel$ and module$ generally we
                        # are likely to have to expand $ISADIR, but we don't
                        # generate such entries now anyway.
                        \#===*) case "$LINE" in
                                End\ of\ LIBBE\ entry*)
                                        [ "$_B" = "$2" -a "$_M" = "$4" ] && \
                                                ENTRY_PRESENT=yes && break
                                        ;;
                                esac ;;
                esac; done < "$GRUB_MENU"
                [ "$_B" = "$2" -a "$_M" = "$4" ] && \
                        ENTRY_PRESENT=yes

                if [ "$ENTRY_PRESENT" = yes ]; then
                        echo "NOTE: Not adding GRUB menu entry into '$GRUB_MENU':" \
                             "'bootfs $2' with 'module $4' already present there"
                        FIREFLY_MENU_TITLE="$_T"
                else
                        echo "Adding GRUB menu entry for failsafe integrated with '$2' into '$GRUB_MENU'"
                        FIREFLY_MENU_TITLE="`basename "$2"` failsafe (amd64${FFVERSUFFIX})"
                        echo "title $FIREFLY_MENU_TITLE
bootfs $2
kernel $3
module $4
#============ End of LIBBE entry =============" >> "$GRUB_MENU"
                fi
        else
                echo "WARNING: Grub menu file not found at '$GRUB_MENU'"
        fi
}

firefly_src_integrated_populate() {
        ### Seed the initial image integrated in the main OS BE, if needed
        ### TODO: See TODO[1] above (for ALTROOTed OS BEs)
        [ "$FIREFLY_CONTAINER_SRC" != "integrated" ] && return 127

        if [ -z "$FIREFLY_CONTAINER_SRCAR" ] || \
           [ ! -s "$FIREFLY_CONTAINER_SRCAR" ] \
        ; then
                [ -n "$FIREFLY_ISO" ] && [ -s "$FIREFLY_ISO" ] \
                || die "No FIREFLY_ISO value or file was found"

                ### Supports ALTROOT $BENEW or current BE (BENEW_MPT=="")
                [ -z "$FIREFLY_CONTAINER_SRCAR" ] && \
                        FIREFLY_CONTAINER_SRCAR="$BENEW_MPT/platform/i86pc/amd64/firefly"

                ### TODO: While this supports arbitrary source archive storage,
                ### method is inherently limited to single file per operation.
                ### If not only "amd64" is to be supported, this needs a loop.
                7z -so x "$FIREFLY_ISO" platform/i86pc/amd64/firefly > "$FIREFLY_CONTAINER_SRCAR" \
                || die "Could not seed baseline Firefly image into '$FIREFLY_CONTAINER_SRCAR'"
                echo "$FIREFLY_BASEVER" > "$FIREFLY_CONTAINER_SRCAR.version"
        else
                echo "INFO: Using an existing FIREFLY_CONTAINER_SRCAR='$FIREFLY_CONTAINER_SRCAR' archive as source"
        fi

        firefly_integrated_addgrub src \
                "$RPOOL_ROOT/$BENEW" \
                "/platform/i86pc/kernel/amd64/unix" \
                "`echo "$FIREFLY_CONTAINER_SRCAR" | sed 's,^'"$BENEW_MPT"'/,/,'`" \
                "$FIREFLY_BASEVER"
}

firefly_tmpimg_unpack_from_beold() {
        ### Mount the baseline image BE
        ### TODO: See TODO[1] above
        [ "$FIREFLY_CONTAINER_SRC" != "standalone" ] && return 127

        beadm mount "$FIREFLY_BEOLD" "$FIREFLY_BEOLD_MPT"
        [ $? = 0 -o $? = 180 ] \
                || die "Could not mount FIREFLY_BEOLD='$FIREFLY_BEOLD' to FIREFLY_BEOLD_MPT='$FIREFLY_BEOLD_MPT'"
        [ -d "$FIREFLY_BEOLD_MPT" ] && ( cd "$FIREFLY_BEOLD_MPT" ) \
                || die "Could not use FIREFLY_BEOLD_MPT='$FIREFLY_BEOLD_MPT'"

        echo "Unpacking a Firefly image file from standalone BE '$FIREFLY_BEOLD'..."
        ### Prepare a copy of the Firefly image for modifications
        mkdir -p "`dirname "$FIREFLY_ARCHIVE_FILE"`"
        gzcat "$FIREFLY_BEOLD_MPT"/platform/i86pc/amd64/firefly > "$FIREFLY_ARCHIVE_FILE" \
                || die "Could not unpack Firefly image file"

        beadm umount "$FIREFLY_BEOLD"
        [ $? = 0 -o $? = 185 ] && rm -rf "$FIREFLY_BEOLD_MPT"
}

firefly_tmpimg_unpack_from_integrated() {
        ### See TODO[1]: Revise for ALTROOT (BENEW) support later
        [ "$FIREFLY_CONTAINER_SRC" != "integrated" ] && return 127

        if [ -z "$FIREFLY_CONTAINER_SRCAR" ] || \
           [ ! -s "$FIREFLY_CONTAINER_SRCAR" ] \
        ; then
                die "Firefly image file FIREFLY_CONTAINER_SRCAR='$FIREFLY_CONTAINER_SRCAR' not found"
        fi

        echo "Unpacking an integrated Firefly image file '$FIREFLY_CONTAINER_SRCAR'..."
        ### Prepare a copy of the Firefly image for modifications
        mkdir -p "`dirname "$FIREFLY_ARCHIVE_FILE"`"
        gzcat "$FIREFLY_CONTAINER_SRCAR" > "$FIREFLY_ARCHIVE_FILE" \
                || die "Could not unpack Firefly image file"
}

firefly_tmpimg_mount() {
        mkdir -p "$FIREFLY_ARCHIVE_MPT"
        mount -F ufs "`lofiadm -a "$FIREFLY_ARCHIVE_FILE"`" "$FIREFLY_ARCHIVE_MPT" \
                || die "Could not mount the temporary Firefly image file"
}

firefly_tmpimg_update_contents() {
        ### Embed the update-script into the mounted new image
        ####################
        echo '#!/bin/sh

# Update the kernel bits in this image (rooted at "current dir" == `pwd`)
# with files from the running system (rooted at $ALTROOT (or "/"))
# (C) 2014-2015 by Jim Klimov
# Generated by beadm-firefly-update.sh
# See https://github.com/jimklimov/illumos-splitroot-scripts

for D in `pwd`/kernel `pwd`/platform; do
 cd "$D" && \
 find . -type f | while read F; do
  RFP="$ALTROOT/platform/$F"; RFK="$ALTROOT/kernel/$F"; RF=""
  [ -s "$RFP" ] && RF="$RFP"
  [ -s "$RFK" -a -z "$RF" ] && RF="$RFK"
  [ -n "$RF" ] && \
   { echo "+++ Got $RF"; cp -pf "$RF" "$F"; } || \
   echo "=== No $RFP nor $RFK !"
  done
done
' > "$FIREFLY_ARCHIVE_MPT"/update-kernel.sh
####################

        [ $? = 0 ] && ( \
                cd "$FIREFLY_ARCHIVE_MPT" && \
                chmod +x update-kernel.sh && \
                echo "INFO: Updating kernel bits in the temporary Firefly image file..." && \
                ALTROOT="$BENEW_MPT" ./update-kernel.sh \
        ) || die "Could not update kernel bits in the temporary Firefly image file"

        (       cd "$FIREFLY_ARCHIVE_MPT/bin" && \
                ls -la sh | grep ksh93 >/dev/null && \
                [ -x ./bash ] && \
                echo "Fixing the default failsafe shell to be BASH..." && \
                { rm -f sh ; ln -s bash sh; }
        )

        echo "INFO: Zeroing out unallocated space..."
        dd if=/dev/zero of="$FIREFLY_ARCHIVE_MPT/bigzero" >/dev/null 2>&1
        rm -f "$FIREFLY_ARCHIVE_MPT/bigzero"
}

firefly_tmpimg_cleanup_mounts() {
        ### Initial clean-up after temporary-image update...
        umount "$FIREFLY_ARCHIVE_MPT" && \
        lofiadm -d "$FIREFLY_ARCHIVE_FILE" && \
        rm -rf "$FIREFLY_ARCHIVE_MPT" \
        || die "Could not clean up the temporary Firefly image mountpoint"
}

firefly_tmpimg_cleanup_files() {
        case "$BENEW_MPT" in
                /tmp/ff-*)
                        echo "INFO: Releasing alternate BENEW='$BENEW'"
                        if [ -x "`dirname "$0"`/beadm-umount.sh" ] ; then
                                echo "Using '`dirname "$0"`/beadm-umount.sh' to ensure that BENEW='$BENEW' is unmounted"
                                "`dirname "$0"`/beadm-umount.sh"
                        fi
                        beadm umount "$BENEW" >/dev/null 2>&1

                        [ $? = 0 -o $? = 185 ] && \
                        [ -d "$BENEW_MPT" ] && \
                                rm -rf "$BENEW_MPT"
                        ;;
                *) ;;
        esac

        rm -f "$FIREFLY_ARCHIVE_FILE" "$FIREFLY_ARCHIVE_FILE_COMPRESSED" "$FIREFLY_ARCHIVE_FILE_COMPRESSED".version \
        || die "Could not clean up the temporary Firefly the image files"
}

trap_cleanup() {
        _EXITCODE=$?
        echo "Signal received, cleaning up as much as we can..."
        # Subprocess to catch die()s
        ( firefly_tmpimg_cleanup_mounts )
        ( firefly_tmpimg_cleanup_files )
        exit ${_EXITCODE}
}

firefly_tmpimg_recompress() {
        echo "Recompressing the updated Firefly image file (gzip$GZIP_LEVEL)..."
        trap "trap_cleanup" 1 2 3 15
        gzip -c $GZIP_LEVEL < "$FIREFLY_ARCHIVE_FILE" > "$FIREFLY_ARCHIVE_FILE_COMPRESSED" \
                || die "Could not recompress the Firefly image file"
        if [ -n "$FIREFLY_BASEVER" ] && [ "$FIREFLY_BASEVER" != "firefly_0000" ]; then
                echo "$FIREFLY_BASEVER" > "$FIREFLY_ARCHIVE_FILE_COMPRESSED".version
        fi
        trap - 1 2 3 15
}

firefly_tgt_standalone_create_mount() {
        ### Store the image file into a BE
        ### TODO[2]: When integrating with common BENEW/BEOLD and storing
        ### "firefly" archives in-place, implement a flag to store in-place
        ### and update menu.lst instead of making a new BE... end-users may
        ### want both options, their choice
        [ "$FIREFLY_CONTAINER_TGT" != "standalone" ] && return 127

        echo "Clone and mount the new FireFly Failsafe BE dataset..."
        if beadm list "$FIREFLY_BENEW" ; then
                die "A Firefly dataset FIREFLY_BENEW='$FIREFLY_BENEW' already exists" \
                    "If you do intend to replace its contents - kill it yourself with" \
                    "  beadm destroy -Ffsv $FIREFLY_BENEW"
        else
                ### NOTE: "beadm create" properly clones the boot-menu block
                FIREFLY_MENU_TITLE="FireFly FailSafe Recovery $FIREFLY_BENEW (auto-updated from $FIREFLY_BEOLD) amd64"
                if ! beadm create \
                    -d "$FIREFLY_MENU_TITLE" \
                    -e "$FIREFLY_BEOLD" "$FIREFLY_BENEW" \
                ; then
                        echo "WARN: Could not clone new Firefly dataset FIREFLY_BENEW='$FIREFLY_BENEW'"
                        echo "FALLBACK: Trying to create a new BE '$FIREFLY_BENEW' from scratch..."
                        ### This dies if fails
                        beadm_create_raw_begin "$FIREFLY_BENEW" "$FIREFLY_BENEW_MPT" && \
                        beadm_create_raw_finish "$FIREFLY_BENEW" "(auto-updated from $FIREFLY_BEOLD)"
                fi
        fi

        beadm mount "$FIREFLY_BENEW" "$FIREFLY_BENEW_MPT"
        [ $? = 0 -o $? = 180 ] \
                || die "Could not mount FIREFLY_BENEW='$FIREFLY_BENEW' to FIREFLY_BENEW_MPT='$FIREFLY_BENEW_MPT'"
        [ -d "$FIREFLY_BENEW_MPT" ] && ( cd "$FIREFLY_BENEW_MPT" ) \
                || die "Could not use FIREFLY_BENEW_MPT='$FIREFLY_BENEW_MPT'"
}

firefly_tgt_standalone_update_files() {
        [ "$FIREFLY_CONTAINER_TGT" != "standalone" ] && return 127
        firefly_tgt_standalone_create_mount || return $?
        echo "Copying updated files into new FireFly Failsafe BE dataset..."

        ### Note that i386 32-bit kernels are not supported by current Firefly
        mkdir -p \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/amd64 \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/kmdb/amd64 \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/amd64

        cp -pf /platform/i86pc/kernel/amd64/unix \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/amd64/unix \
                || die
        cp -pf /platform/i86pc/kernel/kmdb/amd64/unix \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/kmdb/amd64/unix \
                || die
        cp -pf "$FIREFLY_ARCHIVE_FILE_COMPRESSED" \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/amd64/firefly \
                || die

        ls -lda "$FIREFLY_BENEW_MPT"/platform/i86pc/amd64/firefly* \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/amd64/unix \
                "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/kmdb/amd64/unix

        beadm umount "$FIREFLY_BENEW_MPT"
        [ $? = 0 -o $? = 185 ] && rm -rf "$FIREFLY_BENEW_MPT"
}

firefly_tgt_integrated_update_files() {
        ### See TODO[1]: Revise for ALTROOT (BENEW/BENEW_MPT) support later
        [ "$FIREFLY_CONTAINER_TGT" != "integrated" ] && return 127

        echo "Copying updated files into main OS BE dataset..."
        ### Note that i386 32-bit kernels are not supported by current Firefly
        ### TODO: Revise if this changes
        cp -pf "$FIREFLY_ARCHIVE_FILE_COMPRESSED" \
                "$BENEW_MPT"/platform/i86pc/amd64/firefly \
                || die

        if [ -n "$FIREFLY_BASEVER" ] && [ "$FIREFLY_BASEVER" != "firefly_0000" ]; then
                echo "$FIREFLY_BASEVER" > "$BENEW_MPT"/platform/i86pc/amd64/firefly.version
        fi

        [ -s "$BENEW_MPT"/platform/i86pc/amd64/firefly.version ] && \
                echo "NOTE: Original version marked in '$BENEW_MPT/platform/i86pc/amd64/firefly.version' is '`cat "$BENEW_MPT"/platform/i86pc/amd64/firefly.version`'" || \
                echo "WARN: Please record the original 'firefly_MMYY' version into '$BENEW_MPT/platform/i86pc/amd64/firefly.version'"

        ls -lda "$BENEW_MPT"/platform/i86pc/amd64/firefly* \
                "$BENEW_MPT"/platform/i86pc/kernel/amd64/unix \
                "$BENEW_MPT"/platform/i86pc/kernel/kmdb/amd64/unix

        firefly_integrated_addgrub tgt \
                "$RPOOL_ROOT/$BENEW" \
                "/platform/i86pc/kernel/amd64/unix" \
                "/platform/i86pc/amd64/firefly" \
                ""      # Rely on .version file if exists
}

# Overview of functional logic, blocks that are easy to juggle around
initialize_envvars_beadm_firefly
firefly_src_standalone_populate_beold || \
firefly_src_integrated_populate

firefly_tmpimg_unpack_from_beold || \
firefly_tmpimg_unpack_from_integrated

if true; then
firefly_tmpimg_mount
firefly_tmpimg_update_contents
firefly_tmpimg_cleanup_mounts
else GZIP_LEVEL="-3"; fi # Debug noop

firefly_tmpimg_recompress

firefly_tgt_standalone_update_files || \
firefly_tgt_integrated_update_files

firefly_tmpimg_cleanup_files

echo ""
echo "If all went well above, you are ready to reboot into this updated Firefly"
echo "(via manual selection of '$FIREFLY_MENU_TITLE' at boot)"
echo "to recover just like the good old locally-installed failsafe image :)"
