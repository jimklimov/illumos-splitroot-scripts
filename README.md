# illumos-splitroot-scripts
My article on "Split-root installation" of illumos-based OSes resulted
in some code better maintained in Git than in Wiki attachments. See:
http://wiki.openindiana.org/oi/Advanced+-+Split-root+installation

The SMF method scripts and manifests (and/or patches thereto to cater
for the posterity) presented here allow to add support for "split-root"
ZFS root filesystem structure, where the OS image is spread over several
datasets under a common root (which are automatically cloned with the
common `beadm clone` facility, `pkg image-upgrade` and so on).

However, more "correct" creation of BE clones (which would take into
account re-application of the dataset attributes) and subsequently the
installation of packaged updates is conveniently automated with scripts
`beadm-clone.sh` and `beadm-upgrade.sh` included with this project.

Note that while splitting off the `usr` filesystem into its own dataset
with maximum compression is most beneficial, it is also most problematic
in modern default distributions (OpenIndiana Dev and Hipster, OmniOS)
whose `/sbin/sh` is effectively a symlink to `/usr/bin/.../ksh`.
The one-time routine to prepare such installations to become ready for
reliable split-root usage is detailed in the article referenced above.

Parts of the OS filesystem tree, such as `/var/mail` or `/var/logs`,
which a user or developer may want to remain the same (with monotonous
history) across any interim reboots into tested BEs, can be contained
under a common `rpool/SHARED` node (or possibly any other location that
these scripts can find them - but this has not been tested extensively).

Also provided is an optional patch for network-related services which
would reduce or eliminate their dependency on the `/usr` filesystem.

## beadm-firefly-update.sh

A recent addition to this project is a script that aims to help manage
keeping up-to-date the Firefly Failsafe image in a "standalone" bootfs
or "integrated" with an OS rootfs (initial ISO image must be downloaded
by the user). It is integrated with `beadm-upgrade.sh` to update and
embed a failsafe image in newly upgraded BE's, if an original "firefly"
archive is available.

The script is likely to evolve, keep tuned...

Note that beside piggy-backing on ISO releases, there is also a published
recipe at https://github.com/alhazred/firefly which you could use to
maintain your own failsafe archive in a more "correct" manner (e.g. build
yours after updating your system).

See also the original Firefly blog post at
https://alexeremin.blogspot.com/2013/05/firefly-failsafe-image-for-illumos.html

### Installing a Firefly ISO release as a rootfs

The condensed procedure to create a template `firefly_MMYY` rootfs for
automated use with these scripts follows:

1) Fetch current firefly build (e.g. 0516 as of now) from SourceForge:
https://sourceforge.net/projects/fireflyfailsafe/files/latest/download

I clicked in browser to get into "Problems Downloading?" and got a
direct link for `wget`:

````
:; ISOURL='https://downloads.sourceforge.net/project/fireflyfailsafe/firefly_05052016.iso?r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Ffireflyfailsafe%2Ffiles%2Ffirefly_05052016.iso%2Fdownload&ts=1555172974'
:; mkdir -p /export/distribs/firefly-failsafe && \
   cd /export/distribs/firefly-failsafe/ && \
   wget -O firefly_05052016.iso "$ISOURL"
````

2) Make and populate empty new rootfs (uncompressed so any old kernel
likes it):

````
:; zfs create -o mountpoint=/ -o compression=off -o canmount=noauto \
      -o org.opensolaris.libbe:uuid=1d2111c8-f169-43d7-e758-f7d8e4ff0516 \
      rpool/ROOT/firefly_0516

:; beadm mount firefly_0516 /a
:; LOFI_FFISO="`lofiadm -a /export/distribs/firefly-failsafe/firefly_05052016.iso`"
:; mount -F hsfs -o ro "$LOFI_FFISO" /mnt/cdrom

:; rsync -avPHK /mnt/cdrom/ /a/
:; touch /a/reconfigure

:; umount /mnt/cdrom
:; lofiadm -d "$LOFI_FFISO"

:; zfs snapshot rpool/ROOT/firefly_0516@firefly-05052016-original
````

3) One more bit of experience: the procedure referenced above, to maintain
a failsafe archive for my system as I upgrade its OS over time, had
recently hit a wall with the archive running out of space so the
copied-over current kernel did not fit.

Extend the "firefly" boot archive, with 128M here on top of its original
~150M (no big deal, used as a compressed template anyway; however take care
to balance it against the tmpfs storage overhead during upgrades on your
system):

````
:; gzcat /a/platform/i86pc/amd64/firefly > /tmp/fff
:; dd if=/dev/zero bs=4096 count=32768 >> /tmp/fff
:; LOFI_FFUFS="`lofiadm -a /tmp/fff`"
:; RLOFI_FFUFS="`echo "$LOFI_FFUFS" | sed 's,/lofi/,/rlofi/,'`"

:; growfs "$RLOFI_FFUFS"
/dev/rlofi/1:   1386000 sectors in 2310 cylinders of 1 tracks, 600 sectors
        676.8MB in 145 cyl groups (16 c/g, 4.69MB/g, 2240 i/g)
super-block backups (for fsck -F ufs -o b=#) at:
 32, 9632, 19232, 28832, 38432, 48032, 57632, 67232, 76832, 86432,
 1296032, 1305632, 1315232, 1324832, 1334432, 1344032, 1353632, 1363232,
 1372832, 1382432
````

3a) Can check the space reports:

````
:; mount -F ufs -o rw "$LOFI_FFUFS" /mnt/cdrom
:; df -k /mnt/cdrom ; umount "$LOFI_FFUFS"

Filesystem     1K-blocks   Used Available Use% Mounted on
/dev/lofi/1       650061 148447    501614  23% /mnt/cdrom
````

3b) Let go of the LOFI device:

````
:; lofiadm -d "$LOFI_FFUFS"
````

3c) Get the template back into place... tagging the timestamp back to
see when the downloaded content originated:

````
:; touch -r /a/platform/i86pc/amd64/firefly /tmp/fff
:; gzip -9 -c < /tmp/fff > /a/platform/i86pc/amd64/firefly
:; touch -r /tmp/fff /a/platform/i86pc/amd64/firefly
:; zfs snapshot rpool/ROOT/firefly_0516@firefly-05052016-expanded
````

4) Whether or not you expanded the UFS image, tidy up by unmounting
the new rootfs:
````
:; beadm umount /a
````

When you next utter `./beadm-update.sh` or `./beadm-firefly-update.sh`,
your system should use a failsafe enviromnent based on this template
rootfs, if things go south.

Hope this helps,
Jim Klimov
