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

Hope this helps,
Jim Klimov
