#!/bin/bash 
mkdir module
echo "Removing previous kernel source"
rm -rf kernel*.src.rpm*
echo "Downloading kernel source from official repo"
NAME=kernel-$(uname -r | sed 's/.x86_64//').src.rpm
wget https://kojipkgs.fedoraproject.org//packages/kernel/$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')/$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $2}')/src/kernel-$(uname -r | sed 's/.x86_64//').src.rpm
echo "Extracting kernel source"
mkdir extracted
cd extracted
rpm2cpio ../kernel-$(uname -r | sed 's/.x86_64//').src.rpm | cpio -idmv
mv linux-* ../
cd ..
rm -rf extracted
tar xvf $(ls | grep 'linux-*')
rm linux-*.tar.xz
mv linux* linux.src
echo "Extracting files for sony dualshock driver"
cp linux.src/drivers/hid/*sony* ./module
cp linux.src/drivers/hid/*ids* ./module
rm -rf linux.src
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
    [[ -n "$(lsmod | grep hid_sony)" ]] && rmmod hid-sony
    [[ -n "$(lsmod | grep hid_sony)" ]] && rmmod hid-sony-clone-fix
    rm -rf /usr/src/hid-sony*
fi
echo "Copying the module to DKMS"
cp -rf "$(pwd)/module" "/usr/src/hid-sony-clone-fix-$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')"
KERNEL=""
if [[ "$__chroot" -eq 1 ]]; then
    KERNEL="$(ls -1 /lib/modules | tail -n -1)"
else
    KERNEL="$(uname -r)"
fi
echo "Compiling DKMS module"
dkms install -m hid-sony-clone-fix -v "$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')" -k $KERNEL
rmmod hid-sony
modprobe hid-sony-clone-fix
if dkms status | grep -q "^hid-sony-clone-fix"; then
    echo "The script can't detect if everything works, if works please add a blacklist file for the module hid-sony and now use hid-sony-clone-fix"
else
    echo "For this step, you'll need the root password, if you dont have it, please skip and create the file /usr/lib/modprobe.d/hid-sony-blacklist.conf with this content blacklist hid-sony"
    su root -c "echo \"blacklist hid-sony\" > /usr/lib/modprobe.d/hid-sony-blacklist.conf"
fi
rm -rf module
rm kernel*.rpm
