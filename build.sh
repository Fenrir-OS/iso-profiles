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
pacman -Sy artools iso-profiles git grub --noconfirm
buildiso -p base -q
mkdir -p /home/artools-workspace
ln -s ~/artools-workspace /home/artools-workspace
EOF

pushd livefs
mkdir -p ./mnt/usr/share/artools/iso-profiles
mkdir -p ./mnt/home/artools-workspace/iso
mkdir -p ./mnt/home/artools-workspace
cp -r ${FENRIR_DIR} ./mnt/usr/share/artools/iso-profiles
cp -r ${FENRIR_DIR} ./mnt/home/artools-workspace/iso
cp -r ${ISO_DIR} ./mnt/home/artools-workspace

chmod -R 777 ${FENRIR_DIR}
chmod -R 777 ${ISO_DIR}
chmod -R 4755 ./mnt/usr/bin/sudo

# cp -r ${FENRIR_DIR}/live-overlay/usr/share/grub ./mnt/usr/share/grub
# cp -r ${FENRIR_DIR}/root-overlay/etc/default ./mnt/etc/default
popd

cat <<EOF | chroot livefs artix-chroot /mnt /bin/bash -xe -
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
useradd -m -G wheel -s /bin/bash admin
su admin
echo 'Build iso fenrir => Build livefs'
buildiso -p fenrir -i ${EDITION} -x
chmod -R 777 /usr/share/ 
cp -r /usr/share/artools/iso-profiles/fenrir/live-overlay/usr/share/grub /usr/share/
cp -r /usr/share/artools/iso-profiles/fenrir/root-overlay/etc /
echo 'Build iso fenrir => Build rootfs'
buildiso -p fenrir -i ${EDITION} -sc
echo 'Build iso fenrir => Build bootfs'
buildiso -p fenrir -i ${EDITION} -bc
EOF
cat <<EOF | chroot livefs artix-chroot /mnt /bin/bash -xe -
chmod -R 777 /var/lib/artools/buildiso/fenrir
cp /usr/share/artools/iso-profiles/fenrir/live-overlay/usr/share/grub/cfg/* /var/lib/artools/buildiso/fenrir/iso/boot/grub
cp -r /usr/share/artools/iso-profiles/fenrir/live-overlay/usr/share/grub/fenrir /var/lib/artools/buildiso/fenrir/iso/boot/grub
cp -r /usr/share/artools/iso-profiles/fenrir/live-overlay/usr /var/lib/artools/buildiso/fenrir/artix/rootfs
cp -r /usr/share/artools/iso-profiles/fenrir/live-overlay/etc /var/lib/artools/buildiso/fenrir/artix/rootfs
echo 'Build iso fenrir => Generate ISO'
buildiso -p fenrir -i ${EDITION} -zc


cp -r ~/artools-workspace /home/
su
chmod -R 777 /home/admin
EOF

cat <<EOF > rootfs/etc/resolv.conf
# This file was automatically generated by WSL. \
To stop automatic generation of this file, remove this line."
EOF

rm -f rootfs/fakeroot-tcp.pkg rootfs/glibc-linux4.pkg

pushd livefs
mkdir -p ${ISO_DIR}
cp -r ./mnt/home/admin/artools-workspace/iso/fenrir/* ${ISO_DIR}
popd