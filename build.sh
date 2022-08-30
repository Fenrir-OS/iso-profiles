#!/bin/bash -xe

# Warning: this script is not supposed to be run on real system,
# as it will not clean up after itself.
# Use it only in ephemeral environments, such as Travis CI.

CWD=$(realpath $(dirname $0))
BUILD_DIR="$CWD/build/$(date +%s)"
DOWNLOAD_DIR="$CWD/download"
ISO_DIR="$CWD/iso"
FENRIR_DIR="$CWD/fenrir"

mkdir -p $BUILD_DIR
mount --bind $BUILD_DIR $BUILD_DIR
pushd $BUILD_DIR

ln -s ${DOWNLOAD_DIR}/* .

mkdir isofs
mount -t iso9660 -o loop,ro artix.iso isofs
unsquashfs -f -d livefs ./isofs/LiveOS/rootfs.img

mount --bind livefs livefs

pushd livefs
mount -t proc /proc proc/
mount -t sysfs /sys sys/
mount --bind /dev dev/
mount --bind /run run/
mount -t tmpfs /tmp tmp/
mount --bind /etc/resolv.conf etc/resolv.conf
popd

mkdir rootfs
mount --bind rootfs rootfs
mount --bind rootfs livefs/mnt

cat <<EOF | chroot livefs /bin/bash -xe -
pacman-key --init
pacman-key --populate
pacman -Sy artix-keyring artools iso-profiles --noconfirm
basestrap -G -M -c /mnt base base-devel ${EXTRA_PKGS}
basestrap /mnt linux-lts linux-firmware
fstabgen -U /mnt >> /mnt/etc/fstab
pacman -Syu --disable-download-timeout
EOF

echo "LANG=en_US.UTF-8" >> rootfs/etc/locale.conf
sed -i -e "s/#en_US.UTF-8/en_US.UTF-8/" rootfs/etc/locale.gen
sed -i -e "s/#IgnorePkg   =/IgnorePkg   = fakeroot/" rootfs/etc/pacman.conf
cp fakeroot-tcp.pkg glibc-linux4.pkg rootfs/

cat <<EOF | chroot livefs artix-chroot /mnt /bin/bash -xe -
locale-gen
yes | pacman -U /fakeroot-tcp.pkg /glibc-linux4.pkg
pacman-key --init
pacman-key --populate
EOF

cat <<EOF | chroot livefs artix-chroot /mnt /bin/bash -xe -
pacman -Sy artools iso-profiles --noconfirm
modprobe loop
buildiso -p base -q
mkdir /home/artools-workspace
ln -s ~/artools-workspace /home/artools-workspace
EOF

pushd livefs
mkdir -p /mnt/usr/share/artools/iso-profiles/fenrir
mkdir -p /mnt/home/artools-workspace/iso/fenrir
mkdir -p /mnt/home/artools-workspace/fenrir

mount --bind ${FENRIR_DIR} /mnt/usr/share/artools/iso-profiles/fenrir
mount --bind ${FENRIR_DIR} /mnt/home/artools-workspace/iso/fenrir
mount --bind ${ISO_DIR} /mnt/home/artools-workspace/iso/fenrir

chmod -R 777 /usr/share/artools/iso-profiles/fenrir
chmod -R 777 /home/artools-workspace/fenrir

# cp -R ${FENRIR_DIR}/* /usr/share/artools/iso-profiles/fenrir
# cp -R ${ISO_DIR} /home/artools-workspace/iso/fenrir

popd

cat <<EOF | chroot livefs artix-chroot /mnt /bin/bash -xe -
buildiso -p fenrir -i runit
EOF

cat <<EOF > rootfs/etc/resolv.conf
# This file was automatically generated by WSL. \
To stop automatic generation of this file, remove this line."
EOF

rm -f rootfs/fakeroot-tcp.pkg rootfs/glibc-linux4.pkg
