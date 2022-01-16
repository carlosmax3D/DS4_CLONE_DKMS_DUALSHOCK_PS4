# DS4_CLONE_DKMS_FEDORA

Hi everybody.
I figured out that some chinese controllers failed at plug it in the USB connector with the following errors:
- failed to retrieve feature report 0x81 with the DualShock 4 MAC address
- failed to claim input

If you have these error, change your USB cable and try again and if the problem persist you have to patch the kernel driver. 

This script has been customised for Ubuntu, if you want to use it on another distro maybe you have to change some paths but It should works anyway because it uses DKMS.

And also you need a patch file for the code, you need all these files in the same folder and you have to run the script with admin rights.

I hope this help someone
