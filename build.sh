#!/bin/bash

REPO_URL=https://github.com/DHDAXCW/lede-rockchip
REPO_BRANCH=stable
CONFIG_FILE=configs/lean/openwrt.config
CUSTOM_CONF=configs/lean/i2cy.config
DIY_SH=scripts/lean.sh
KMODS_IN_FIRMWARE=true
UPLOAD_RELEASE=true
TZ=Asia/Shanghai

MAX_THREADS=64


echo "[build.sh]: clone sources..."
df -hT $PWD
I2BUILD_ROOT=$PWD
git clone $REPO_URL -b $REPO_BRANCH openwrt

echo "[build.sh]: updating feeds..."
cd openwrt
OPENWRTROOT=$PWD

git clone --depth=1 https://github.com/DHDAXCW/packages customfeeds/packages
git clone --depth=1 https://github.com/DHDAXCW/luci customfeeds/luci
chmod +x ../scripts/*.sh
../scripts/hook-feeds.sh

echo "[build.sh]: installing feeds..."
cd $OPENWRTROOT
./scripts/feeds install -a

echo "[build.sh]: loading custom configurations..."
cd $I2BUILD_ROOT
[ -e files ] && mv files $OPENWRTROOT/files
[ -e $CONFIG_FILE ] && mv $CONFIG_FILE $OPENWRTROOT/.config
cat $CUSTOM_CONF >> $OPENWRTROOT/.config
chmod +x scripts/*.sh
cd $OPENWRTROOT
../$DIY_SH
../scripts/preset-clash-core.sh amd64
../scripts/preset-terminal-tools.sh
make defconfig

echo "[build.sh]: downloading packages..."
cd $OPENWRTROOT
cat .config
make download -j50
make download -j1
find dl -size -1024c -exec ls -l {} \;
find dl -size -1024c -exec rm -f {} \;

echo "[build.sh]: compile packages..."
cd $OPENWRTROOT
echo -e "$(MAX_THREADS) thread compile"
make tools/compile -j$(MAX_THREADS) || make tools/compile -j$(MAX_THREADS)
make toolchain/compile -j$(MAX_THREADS) || make toolchain/compile -j$(MAX_THREADS)
make target/compile -j$(MAX_THREADS) || make target/compile -j$(MAX_THREADS) IGNORE_ERRORS=1
make diffconfig
make package/compile -j$(MAX_THREADS) IGNORE_ERRORS=1 || make package/compile -j$(MAX_THREADS) IGNORE_ERRORS=1
make package/index
cd $OPENWRTROOT/bin/packages/*
PLATFORM=$(basename `pwd`)
cd *
SUBTARGET=$(basename `pwd`)
FIRMWARE=$PWD

echo "[build.sh]: generating firmware..."
cd $I2BUILD_ROOT/configs/opkg
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
