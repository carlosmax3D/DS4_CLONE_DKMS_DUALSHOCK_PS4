# DS4_CLONE_DKMS_FEDORA

Hi everybody.
I figured out that some chinese controllers failed at plug it in the USB connector with the following errors:
- failed to retrieve feature report 0x81 with the DualShock 4 MAC address
- failed to claim input
If you have these error, change your USB cable and try again and if the problem persist you have to patch the kernel driver. I made a script for fedora, if you want to use it on Ubuntu or another distro maybe you have to change some paths but It should works anyway because it uses DKMS.
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
`make -C /lib/modules/\$(KVERSION)/build V=1 M=\$(PWD) modules`
clean:
`test ! -d /lib/modules/\$(KVERSION) || make -C /lib/modules/\$(KVERSION)/build V=1 M=\$(PWD) clean`
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
And also you need a patch file for the code, you need these files in the same folder and you have to run the script with admin rights.
--- hid-sony.c. 2020-10-30 16:55:38.255114700 -0600
+++ hid-sony.c 2020-10-30 17:03:10.112308500 -0600
@@ -2084,6 +2084,7 @@
`struct sixaxis_output_report *report =`

	`(struct sixaxis_output_report *)sc->output_report_dmabuf;`

`int n;`
+ int ret;
`/* Initialize the report with default values */`

`memcpy(report, &default_report, sizeof(struct sixaxis_output_report));`
@@ -2122,10 +2123,20 @@
`if (sc->quirks & SHANWAN_GAMEPAD)`

	`hid_hw_output_report(sc->hdev, (u8 *)report,`
sizeof(struct sixaxis_output_report));
- else
- hid_hw_raw_request(sc->hdev, report->report_id, (u8 *)report,
+ else {
+ /*
+ * Gasia controller workaround
+ * See: https://bugzilla.kernel.org/show_bug.cgi?id=200009
+ */
+ ret = hid_hw_raw_request(sc->hdev, report->report_id, (u8 *)report,
sizeof(struct sixaxis_output_report),
HID_OUTPUT_REPORT, HID_REQ_SET_REPORT);
+ if (ret < 0) {
+ hid_err(sc->hdev, "failed to send raw request, attempting fallback\n");
+ hid_hw_output_report(sc->hdev, (u8 *)report,
+ sizeof(struct sixaxis_output_report));
+ }
+ }
}
static void dualshock4_send_output_report(struct sony_sc *sc)
@@ -2483,10 +2494,10 @@
* retrieved with feature report 0x81. The address begins at
* offset 1.
*/
- ret = hid_hw_raw_request(sc->hdev, 0x81, buf,
+ /*ret = hid_hw_raw_request(sc->hdev, 0x81, buf,
DS4_FEATURE_REPORT_0x81_SIZE, HID_FEATURE_REPORT,
- HID_REQ_GET_REPORT);
-
+ HID_REQ_GET_REPORT);*/
+ ret = DS4_FEATURE_REPORT_0x81_SIZE;
	`if (ret != DS4_FEATURE_REPORT_0x81_SIZE) {`
hid_err(sc->hdev, "failed to retrieve feature report 0x81 with the DualShock 4 MAC address\n");
ret = ret < 0 ? ret : -EINVAL;
I hope this help someone
