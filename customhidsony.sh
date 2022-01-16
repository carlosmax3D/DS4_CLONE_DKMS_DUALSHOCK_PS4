#!/bin/bash 
mkdir module

echo "Downloading the kernel source package"
sudo apt-get -y install dpkg-dev

pushd /tmp 
apt-get source linux
popd

PACKAGE_VERSION="$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')"

cp /tmp/linux-$PACKAGE_VERSION/drivers/hid/{hid-ids.h,hid-sony.c} ./module

echo "Patching driver"
patch -u -b ./module/hid-sony.c -i cloneDualshock.patch
mv ./module/hid-sony.c ./module/hid-sony-clone-fix.c
rm ./module/*.c.orig

echo "Creating files for building"
cat > "./module/Makefile" << _EOF_
obj-m = hid-sony-clone-fix.o

KVERSION = \$(shell uname -r)
all:
	make -C /lib/modules/\$(KVERSION)/build V=1 M=\$(PWD) modules
clean:
	test ! -d /lib/modules/\$(KVERSION) || make -C /lib/modules/\$(KVERSION)/build V=1 M=\$(PWD) clean
_EOF_
cp ./module/Makefile ./module/Makefile.cross
cat > "./module/dkms.conf" << _EOF_
PACKAGE_NAME="hid-sony-clone-fix"
PACKAGE_VERSION="$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')"
CLEAN="make clean"
MAKE[0]="make KVERSION=\$kernelver"
DEST_MODULE_LOCATION[0]="/kernel/drivers/hid"
BUILT_MODULE_NAME[0]="hid-sony-clone-fix"
DEST_MODULE_LOCATION[0]="/updates/dkms"
AUTOINSTALL="yes"
_EOF_
echo "Stopping inbuilt and new module"
if dkms status | grep -q "^hid-sony"; then
    [[ -n "$(lsmod | grep hid_sony)" ]] && sudo rmmod hid-sony
    [[ -n "$(lsmod | grep hid_sony)" ]] && sudo rmmod hid-sony_clone_fix
    sudo rm -rf /usr/src/hid-sony*
fi

VERSION="$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')"

echo "Copying the module to DKMS"
sudo cp -rf "$(pwd)/module" "/usr/src/hid-sony-clone-fix-$VERSION"

KERNEL="$(uname -r)"

echo "Compiling DKMS module"
sudo dkms install -m hid-sony-clone-fix -v "$VERSION" -k $KERNEL
sudo rmmod hid-sony
sudo modprobe hid-sony-clone-fix
if dkms status | grep -q "^hid_sony_clone_fix"; then
    echo "The script can't detect if everything works, if works please add a blacklist file for the module hid-sony and now use hid-sony-clone-fix"
else
    echo "blacklist hid-sony" | sudo tee /etc/modprobe.d/hid-sony-blacklist.conf > /dev/null
fi

rm -rf module

