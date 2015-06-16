#!/bin/bash

### Keep the Firefly failsafe image for illumos up-to-date
### See https://www.blogger.com/comment.g?blogID=3094974977265128267&postID=6716498883875252619
### Script Copyright (C) 2014-2015 by Jim Klimov
### Firefly Copyright (C) by Alex Eremin aka "alhazred"

### NOTE: This is an experimental work in progress. This script does function,
### but it is likely that some time in the future this split-root project's
### common variables BENEW and BEOLD will refer to "production OS" BEs.
### Then there will be a way to produce a Firefly BE tailored to the newly
### upgraded OS version.
### Another related venue of research is to keep the Firefly archive image in
### the current BE (along with its version of the "unix" binary) so booting
### into the recovery mode is just a matter of attaching another "module$".
### This saves some hassle with extra BE's (may cause scalability problems).

die () {
        echo "" >&2
        while [ $# != 0 ]; do echo "$1"; shift; done >&2
        echo "FATAL ERROR occurred, bailing out (see details above, clean up accordingly" >&2
        exit 1
}

### Pre-requisite: Download the Firefly ISO image from SourceForge project
### http://sourceforge.net/projects/fireflyfailsafe/files/ to your $DOWNLOADDIR
[ -z "$DOWNLOADDIR" ] && \
        DOWNLOADDIR="/export/distribs"

### The latest (by ctime of the file) baseline Firefly version from ISO filename
[ -z "$FIREFLY_ISO" ] && \
        FIREFLY_ISO="`ls --sort=time --time=ctime -1 ${DOWNLOADDIR}/firefly*.iso | head -1`"
[ -n "$FIREFLY_ISO" ] && \
        FIREFLY_ISO="`ls -1 $FIREFLY_ISO`" && \
        [ -s "$FIREFLY_ISO" ] \
        || die "No FIREFLY_ISO found"
[ -z "$FIREFLY_BEOLD" ] && \
        FIREFLY_BEOLD="`basename "$FIREFLY_ISO" .iso`"
[ $? = 0 -a -n "$FIREFLY_BEOLD" ] || die "No FIREFLY_BEOLD found"
### ... example resulting string:
#FIREFLY_BEOLD="firefly_0215"

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

### The new Firefly BE to be updated with files from FIREFLY_BEOLD
[ -z "$FIREFLY_BENEW" ] && FIREFLY_BENEW="${FIREFLY_BEOLD}-${CURRENT_BE}"

### Mountpoints. Current BE is assumed to be at root "/" :)
[ -z "$FIREFLY_BENEW_MPT" ] && FIREFLY_BENEW_MPT="/tmp/ff-$FIREFLY_BENEW"
[ -z "$FIREFLY_BEOLD_MPT" ] && FIREFLY_BEOLD_MPT="/tmp/ff-$FIREFLY_BEOLD"
### Here we'll lofi-mount the temporary Firefly image (archive) file
[ -z "$FFARCH_MPT" ] && FFARCH_MPT="/tmp/ff-$FIREFLY_BEOLD.img-mpt"
[ -z "$FFARCH_FILE" ] && FFARCH_FILE="/tmp/ff-$FIREFLY_BEOLD.img"

if [ -z "$GRUB_MENU" ]; then
	[ -z "$RPOOLALT" ] && \
	    ALTROOT_ARG="" || \
	    ALTROOT_ARG="-R $RPOOLALT"
        GRUB_MENU="`LANG=C bootadm list-menu $ALTROOT_ARG | grep 'the location for the active GRUB menu is' | awk '{print $NF}'`"
        [ $? = 0 ] && [ -n "$GRUB_MENU" ] \
        || GRUB_MENU="$RPOOLALT/rpool/boot/grub/menu.lst"
fi

### Seed the initial image, if needed
if ! beadm list "$FIREFLY_BEOLD" ; then
        zfs create \
            -o mountpoint="$FIREFLY_BEOLD_MPT" -o canmount=noauto \
            $RPOOL_ROOT/"$FIREFLY_BEOLD" && \
        zfs mount "$RPOOL_ROOT/$FIREFLY_BEOLD" && \
        ( cd "$RPOOLALT$FIREFLY_BEOLD_MPT" && 7z x "$DOWNLOADDIR/$FIREFLY_BEOLD.iso" ) \
        || die "Could not seed baseline Firefly dataset FIREFLY_BEOLD='$FIREFLY_BEOLD'"
        zfs umount "$RPOOL_ROOT/$FIREFLY_BEOLD"

        if [ -s "$GRUB_MENU" ] && ! egrep "^bootfs $RPOOL_ROOT/$FIREFLY_BEOLD\$" "$GRUB_MENU"; then
            echo "Adding GRUB menu entry to use and to clone with 'beadm -e' later into '$GRUB_MENU'"
            echo "title FireFly FailSafe Recovery $FIREFLY_BEOLD (from ISO) amd64
bootfs $RPOOL_ROOT/$FIREFLY_BEOLD
kernel /platform/i86pc/kernel/amd64/unix
module /platform/i86pc/amd64/firefly
#============ End of LIBBE entry =============" >> "$GRUB_MENU"
	else
	    echo "WARNING: Grub menu file not found at '$GRUB_MENU'"
        fi
fi

### Clone and mount the new FF dataset to refresh the image from Current BE
if beadm list "$FIREFLY_BENEW" ; then
        die "A Firefly dataset FIREFLY_BENEW='$FIREFLY_BENEW' already exists" \
            "If you do intend to replace its contents - kill it yourself with" \
            "  beadm destoy -Ffsv $FIREFLY_BENEW"
else
        beadm create \
            -d "FireFly FailSafe Recovery $FIREFLY_BENEW (auto-updated from $FIREFLY_BEOLD)" \
            -e "$FIREFLY_BEOLD" "$FIREFLY_BENEW" \
        || die "Could not clone new Firefly dataset FIREFLY_BENEW='$FIREFLY_BENEW'"
fi
beadm mount "$FIREFLY_BENEW" "$FIREFLY_BENEW_MPT"
[ $? = 0 -o $? = 180 ] \
        || die "Could not mount FIREFLY_BENEW='$FIREFLY_BENEW' to FIREFLY_BENEW_MPT='$FIREFLY_BENEW_MPT'"
[ -d "$FIREFLY_BENEW_MPT" ] && ( cd "$FIREFLY_BENEW_MPT" ) \
        || die "Could not use FIREFLY_BENEW_MPT='$FIREFLY_BENEW_MPT'"

### Prepare a copy of the Firefly image for modifications
gzcat "$FIREFLY_BENEW_MPT"/platform/i86pc/amd64/firefly > "$FFARCH_FILE" \
        || die "Could not unpack Firefly image file"
mkdir -p "$FFARCH_MPT"
mount -F ufs "`lofiadm -a "$FFARCH_FILE"`" "$FFARCH_MPT" \
        || die "Could not mount the temporary Firefly image file"

### Embed the update-script into the new image
####################
echo '#!/bin/sh

# Update the kernel bits in this image (rooted at "current dir" == `pwd`)
# with files from the running system (rooted at "/")
# (C) 2014 by Jim Klimov

for D in `pwd`/kernel `pwd`/platform; do
 cd "$D" && \
 find . -type f | while read F; do
  RFP="/platform/$F"; RFK="/kernel/$F"; RF=""
  [ -s "$RFP" ] && RF="$RFP"
  [ -s "$RFK" -a -z "$RF" ] && RF="$RFK"
  [ -n "$RF" ] && \
   { echo "+++ Got $RF"; cp -pf "$RF" "$F"; } || \
   echo "=== No $RFP nor $RFK !"
  done
done
' > "$FFARCH_MPT"/update-kernel.sh
####################

[ $? = 0 ] && ( \
        cd "$FFARCH_MPT" && \
        chmod +x update-kernel.sh && \
        echo "Updating kernel bits in the temporary Firefly image file..." && \
        ./update-kernel.sh \
) || die "Could not update kernel bits in the temporary Firefly image file"

### Clean up...
umount "$FFARCH_MPT" && \
lofiadm -d "$FFARCH_FILE" && \
rm -rf "$FFARCH_MPT" \
|| die "Could not clean up the temporary Firefly image mountpoint"

### Note that i386 32-bit kernels are not supported by current Firefly
cp -pf /platform/i86pc/kernel/amd64/unix \
        "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/amd64/unix \
        || die
cp -pf /platform/i86pc/kernel/kmdb/amd64/unix \
        "$FIREFLY_BENEW_MPT"/platform/i86pc/kernel/kmdb/amd64/unix \
        || die

echo "Recompressing the updated Firefly image file..."
gzip -c -9 < "$FFARCH_FILE" > "$FIREFLY_BENEW_MPT"/platform/i86pc/amd64/firefly \
        || die "Could not recompress the Firefly image file"

beadm umount "$FIREFLY_BENEW_MPT" && \
rm -f "$FFARCH_FILE" || \
die "Could not clean up the temporary Firefly the image file"

echo "If all went well above, you are ready to reboot into this updated Firefly"
echo "(via manual selection of '$FIREFLY_BENEW' at boot)"
echo "to recover just like the good old locally-installed failsafe image :)"
