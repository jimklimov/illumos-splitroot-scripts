#!/bin/bash

### Keep the Firefly failsafe image for illumos up-to-date
### See https://www.blogger.com/comment.g?blogID=3094974977265128267&postID=6716498883875252619
### Script Copyright (C) 2014-2015 by Jim Klimov
### Firefly Copyright (C) by Alex Eremin aka "alhazred"

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
[ -z "$BEOLD" ] && \
        BEOLD="`basename "$FIREFLY_ISO" .iso`"
[ $? = 0 -a -n "$BEOLD" ] || die "No BEOLD found"
### ... example resulting string:
#BEOLD="firefly_0215"

### The current BE name, will be used to pick up updated files
### to refresh the FF image, and to partially name the new FF BE
CURRENT_BE="`beadm list -H | while IFS=";" read BENAME BEGUID BEACT BEMPT BESPACE BEPOLICY BESTAMP; do case "$BEACT" in *N*) echo "$BENAME";; esac; done`" \
        || die "No CURRENT_BE found"

### The new Firefly BE to be updated with files from BEOLD
[ -z "$BENEW" ] && BENEW="${BEOLD}-${CURRENT_BE}"

### Mountpoints. Current BE is assumed to be at root "/" :)
[ -z "$BENEW_MPT" ] && BENEW_MPT="/tmp/ff-$BENEW"
[ -z "$BEOLD_MPT" ] && BEOLD_MPT="/tmp/ff-$BEOLD"
### Here we'll lofi-mount the archive file
[ -z "$FFARCH_MPT" ] && FFARCH_MPT="/tmp/ff-$BEOLD.img-mpt"
[ -z "$FFARCH_FILE" ] && FFARCH_FILE="/tmp/ff-$BEOLD.img"

### Seed the initial image, if needed
if ! beadm list "$BEOLD" ; then
        beadm create \
            -d "FireFly FailSafe Recovery $BEOLD (from ISO)" "$BEOLD" && \
        beadm mount "$BEOLD" "$BEOLD_MPT" && \
        ( cd "$BEOLD_MPT" && 7z x "$DOWNLOADDIR/$BEOLD.iso" ) \
        || die "Could not seed baseline Firefly dataset BEOLD='$BEOLD'"
        beadm umount "$BEOLD"
fi

### Clone and mount the new FF dataset to refresh the image from Current BE
if beadm list "$BENEW" ; then
        die "A Firefly dataset BENEW='$BENEW' already exists" \
            "If you do intend to replace its contents - kill it yourself with" \
            "  beadm destoy -Ffsv $BENEW"
else
        beadm create \
            -d "FireFly FailSafe Recovery $BENEW (auto-updated from $BEOLD)" \
            -e "$BEOLD" "$BENEW" \
        || die "Could not clone new Firefly dataset BENEW='$BENEW'"
fi
beadm mount "$BENEW" "$BENEW_MPT"
[ $? = 0 -o $? = 180 ] \
        || die "Could not mount BENEW='$BENEW' to BENEW_MPT='$BENEW_MPT'"
[ -d "$BENEW_MPT" ] && ( cd "$BENEW_MPT" ) \
        || die "Could not use BENEW_MPT='$BENEW_MPT'"

### Prepare a copy of the Firefly image for modifications
gzcat "$BENEW_MPT"/platform/i86pc/amd64/firefly > "$FFARCH_FILE" \
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
        "$BENEW_MPT"/platform/i86pc/kernel/amd64/unix \
        || die
cp -pf /platform/i86pc/kernel/kmdb/amd64/unix \
        "$BENEW_MPT"/platform/i86pc/kernel/kmdb/amd64/unix \
        || die

echo "Recompressing the updated Firefly image file..."
gzip -c -9 < "$FFARCH_FILE" > "$BENEW_MPT"/platform/i86pc/amd64/firefly \
        || die "Could not recompress the Firefly image file"

beadm umount "$BENEW_MPT" && \
rm -f "$FFARCH_FILE" || \
die "Could not clean up the temporary Firefly the image file"

echo "If all went well above, you are ready to reboot into this updated Firefly"
echo "(via manual selection of '$BENEW' at boot)"
echo "just like the good old locally-installed failsafe image :)"
