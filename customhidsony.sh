#!/bin/bash 
OS_VER=$(lsb_release -a)
VERSION="$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')"
KERNEL=""
if echo ${OS_VER^^} | grep -q "FEDORA"; then
    OS_VER="Fedora"
else
    OS_VER="Ubuntu"
fi
mkdir module

if [ ${OS_VER} = "Fedora" ]; then
	echo "Removing previous kernel source"
	echo "Downloading the kernel source from official repo"
	rm -rf kernel*.src.rpm*
	NAME=kernel-$(uname -r | sed 's/.x86_64//').src.rpm
	wget https://kojipkgs.fedoraproject.org//packages/kernel/$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')/$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $2}')/src/kernel-$(uname -r | sed 's/.x86_64//').src.rpm
	echo "Extracting kernel source"
	mkdir extracted
	cd extracted
	rpm2cpio ../kernel-$(uname -r | sed 's/.x86_64//').src.rpm | cpio -idmv
	mv linux-* ../
	cd ..
	rm -rf extracted
	tar xvf $(ls | grep 'linux-*' | grep 'tar.xz')
	rm linux-*
	mv linux* linux.src
	echo "Extracting files for sony dualshock driver"
	cp linux.src/drivers/hid/*sony* ./module
	cp linux.src/drivers/hid/*ids* ./module
	rm -rf linux.src
	rm -rf linux-*
else
	echo "Downloading the kernel source package"
	sudo apt-get -y install dpkg-dev

	pushd /tmp 
	apt-get source linux
	popd

	PACKAGE_VERSION="$(uname -r | sed 's/.x86_64//' | sed s/-/\ /g | awk -F " " '{print $1}')"

	cp /tmp/linux-$PACKAGE_VERSION/drivers/hid/{hid-ids.h,hid-sony.c} ./module
fi
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

if [ ${OS_VER} = "Fedora" ]; then
	if dkms status | grep -q "^hid-sony"; then
	    [[ -n "$(lsmod | grep hid_sony)" ]] && rmmod hid-sony
	    [[ -n "$(lsmod | grep hid_sony)" ]] && rmmod hid-sony-clone-fix
	    rm -rf /usr/src/hid-sony*
	fi
else
	if dkms status | grep -q "^hid-sony"; then
	    [[ -n "$(lsmod | grep hid_sony)" ]] && sudo rmmod hid-sony
	    [[ -n "$(lsmod | grep hid_sony)" ]] && sudo rmmod hid-sony_clone_fix
	    sudo rm -rf /usr/src/hid-sony*
	fi
fi
echo "Copying the module to DKMS"
if [ ${OS_VER} = "Fedora" ]; then
	cp -rf "$(pwd)/module" "/usr/src/hid-sony-clone-fix-$VERSION"
	if [[ "$__chroot" -eq 1 ]]; then
	    KERNEL="$(ls -1 /lib/modules | tail -n -1)"
	else
	    KERNEL="$(uname -r)"
	fi
else
	sudo cp -rf "$(pwd)/module" "/usr/src/hid-sony-clone-fix-$VERSION"

	KERNEL="$(uname -r)"
fi

echo "Compiling DKMS module"
if [ ${OS_VER} = "Fedora" ]; then
	dkms install -m hid-sony-clone-fix -v "$VERSION" -k $KERNEL
	rmmod hid-sony
	modprobe hid-sony-clone-fix
	if dkms status | grep -q "^hid-sony-clone-fix"; then
	    echo "The script can't detect if everything works, if works please add a blacklist file for the module hid-sony and now use hid-sony-clone-fix"
	else
	    echo "For this step, you'll need the root password, if you dont have it, please skip and create the file /usr/lib/modprobe.d/hid-sony-blacklist.conf with this content blacklist hid-sony"
	    su root -c "echo \"blacklist hid-sony\" > /usr/lib/modprobe.d/hid-sony-blacklist.conf"
	fi
	rm kernel*.rpm
else
	sudo dkms install -m hid-sony-clone-fix -v "$VERSION" -k $KERNEL
	sudo rmmod hid-sony
	sudo modprobe hid-sony-clone-fix
	if dkms status | grep -q "^hid_sony_clone_fix"; then
	    echo "The script can't detect if everything works, if works please add a blacklist file for the module hid-sony and now use hid-sony-clone-fix"
	else
	    echo "blacklist hid-sony" | sudo tee /etc/modprobe.d/hid-sony-blacklist.conf > /dev/null
	fi
fi
rm -rf module
