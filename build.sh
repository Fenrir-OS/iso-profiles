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
pacman -Sy artools iso-profiles git --noconfirm
buildiso -p base -q
mkdir /home/artools-workspace
ln -s ~/artools-workspace /home/artools-workspace
cp /etc/artools/artools.conf ~/.config/artools
cp /usr/share/artools/iso-profiles ~/artools-workspace/

cd ~
git clone https://github.com/Fenrir-OS/iso-profiles
chmod -R 777 iso-profiles

mkdir -p ~/artools-workspace/fenrir
mkdir -p /usr/share/artools/iso-profiles/fenrir
cp /iso-profiles/fenrir ~/artools-workspace/fenrir
cp /usr/share/artools/iso-profiles/fenrir
echo $(ls)
buildiso -p fenrir -i runit
EOF

pushd livefs
echo $(ls)
cp -p /mnt/home/artools-workspace/iso/fenrir ${ISO_DIR}
popd

cat <<EOF > rootfs/etc/resolv.conf
# This file was automatically generated by WSL. \
To stop automatic generation of this file, remove this line."
EOF

rm -f rootfs/fakeroot-tcp.pkg rootfs/glibc-linux4.pkg
