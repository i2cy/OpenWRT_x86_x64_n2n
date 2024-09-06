#!/bin/bash

REPO_URL=https://github.com/DHDAXCW/lede-rockchip
REPO_BRANCH=stable
CONFIG_FILE=configs/lean/openwrt.config
CUSTOM_CONF=configs/lean/i2cy.config
DIY_SH=scripts/lean.sh
export KMODS_IN_FIRMWARE=true
export UPLOAD_RELEASE=true
export TZ=Asia/Shanghai

export nproc=64

echo "[build.sh]: updating environments..."
sudo apt update -y
sudo apt full-upgrade -y
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext gcc-multilib g++-multilib \
git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev libglib2.0-dev libgmp3-dev \
libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libpython3-dev libreadline-dev \
libssl-dev libtool lrzsz mkisofs msmtp ninja-build p7zip p7zip-full patch pkgconf python2.7 python3 \
python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools subversion swig texinfo \
uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev


echo "[build.sh]: clone sources..."
df -hT $PWD
export GITHUB_WORKSPACE=$PWD
git clone $REPO_URL -b $REPO_BRANCH openwrt

echo "[build.sh]: updating feeds..."
cd openwrt
export OPENWRTROOT=$PWD
mkdir customfeeds
git clone --depth=1 https://github.com/DHDAXCW/packages customfeeds/packages
git clone --depth=1 https://github.com/DHDAXCW/luci customfeeds/luci
chmod +x ../scripts/*.sh
../scripts/hook-feeds.sh

echo "[build.sh]: installing feeds..."
cd $GITHUB_WORKSPACE
cd $OPENWRTROOT
./scripts/feeds install -a

echo "[build.sh]: loading custom configurations..."
cd $GITHUB_WORKSPACE
[ -e files ] && mv files $OPENWRTROOT/files
[ -e $CONFIG_FILE ] && mv $CONFIG_FILE $OPENWRTROOT/.config
cat $CUSTOM_CONF >> $OPENWRTROOT/.config
chmod +x scripts/*.sh
cd $OPENWRTROOT
../$DIY_SH
../scripts/preset-clash-core.sh amd64
../scripts/preset-terminal-tools.sh
make defconfig
make menuconfig

echo "[build.sh]: downloading packages..."
cd $GITHUB_WORKSPACE
cd $OPENWRTROOT
cat .config
make download -j50
make download -j1
find dl -size -1024c -exec ls -l {} \;
find dl -size -1024c -exec rm -f {} \;

echo "[build.sh]: compile packages..."
cd $GITHUB_WORKSPACE
cd $OPENWRTROOT
echo -e "$(nproc) thread compile"
make tools/compile -j$(nproc) || make tools/compile -j$(nproc)
make toolchain/compile -j$(nproc) || make toolchain/compile -j$(nproc)
make target/compile -j$(nproc) || make target/compile -j$(nproc) IGNORE_ERRORS=1
make diffconfig
make package/compile -j$(nproc) IGNORE_ERRORS=1 || make package/compile -j$(nproc) IGNORE_ERRORS=1
make package/index
cd $OPENWRTROOT/bin/packages/*
export PLATFORM=$(basename `pwd`)
cd *
export SUBTARGET=$(basename `pwd`)
export FIRMWARE=$PWD

echo "[build.sh]: generating firmware..."
cd $GITHUB_WORKSPACE
cd configs/opkg
sed -i "s/subtarget/$SUBTARGET/g" distfeeds*.conf
sed -i "s/target\//$TARGET\//g" distfeeds*.conf
sed -i "s/platform/$PLATFORM/g" distfeeds*.conf
cd $OPENWRTROOT
mkdir -p files/etc/uci-defaults/
cp ../scripts/init-settings.sh files/etc/uci-defaults/99-init-settings
mkdir -p files/etc/opkg
cp ../configs/opkg/distfeeds-packages-server.conf files/etc/opkg/distfeeds.conf.server
if "$KMODS_IN_FIRMWARE" = 'true'
then
    mkdir -p files/www/snapshots
    cp -r bin/targets files/www/snapshots
    cp ../configs/opkg/distfeeds-18.06-local.conf files/etc/opkg/distfeeds.conf
else
    cp ../configs/opkg/distfeeds-18.06-remote.conf files/etc/opkg/distfeeds.conf
fi
cp files/etc/opkg/distfeeds.conf.server files/etc/opkg/distfeeds.conf.mirror
sed -i "s/http:\/\/192.168.123.100:2345\/snapshots/https:\/\/openwrt.cc\/snapshots\/$(date +"%Y-%m-%d")\/lean/g" files/etc/opkg/distfeeds.conf.mirror
make package/install -j$(nproc) || make package/install -j1 V=s
make target/install -j$(nproc) || make target/install -j1 V=s
pushd bin/targets/x86/64
#rm -rf openwrt-x86-64-generic-kernel.bin
#rm -rf openwrt-x86-64-generic-rootfs.tar.gz
#rm -rf openwrt-x86-64-generic-squashfs-rootfs.img.gz
#rm -rf openwrt-x86-64-generic-squashfs-combined-efi.vmdk
#rm -rf openwrt-x86-64-generic.manifest
mv openwrt-x86-64-generic-squashfs-combined-efi.img.gz $(date +"%Y.%m.%d")-docker-openwrt-x86-64-squashfs-efi.img.gz
popd
make checksum

echo "[build.sh] build complete"
