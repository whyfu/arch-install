#!/bin/bash

echo "[General]
EnableNetworkConfiguration=true
EnableIPv6=true" > /etc/iwd/main.conf

echo "Server = https://mirrors.rit.edu/archlinux/\$repo/os/\$arch
Server = http://phinau.de/arch/\$repo/os/\$arch
Server = https://phinau.de/arch/\$repo/os/\$arch
Server = https://cloudflaremirrors.com/archlinux/\$repo/os/\$arch
" > /etc/pacman.d/mirrorlist

# x86-64_v3 binaries from ALHP repos
curl -o alhp-mirrorlist https://somegit.dev/ALHP/alhp-mirrorlist/raw/branch/master/mirrorlist
cp alhp-mirrorlist /etc/pacman.d/
sed 's/#Server/Server/' -i /etc/pacman.d/alhp-mirrorlist
curl -O https://somegit.dev/ALHP/alhp-keyring/raw/branch/master/alhp.gpg
echo "downloaded alhp repo files"

# alhp v3 repo keys
pacman-key -a alhp.gpg
pacman-key --lsign-key 2E3B2B05A332A7DB9019797848998B4039BED1CA
pacman-key --lsign-key 0D4D2FDAF45468F3DDF59BEDE3D0D2CD3952E298

# chaotic aur repo keys
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

if ! grep -Fq "core-x86-64-v3" /etc/pacman.conf;
then
	sed 's/#VerbosePkgLists/VerbosePkgLists/' -i /etc/pacman.conf
	sed 's/#ParallelDownloads/ParallelDownloads/' -i /etc/pacman.conf
	sed -z 's/#\[multilib\]\n#/[multilib-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n[multilib]\n/' -i /etc/pacman.conf
	sed -z 's/default mirrors./default mirrors.\n\n[core-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n[extra-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist/' -i /etc/pacman.conf
	echo $'[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' >> /etc/pacman.conf
fi

pacman -Syy

cat <<EOF > nvme0n1.sfdisk
label: gpt
unit: sectors
first-lba: 34
last-lba: 1000215182
sector-size: 512

start=, size=      614400, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
start=, size=, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF

read -p "Format? <y/N>: " prompt1
if [ $prompt1 == "y" ]
then
	# WIPE disk
	wipefs -a -f /dev/nvme0n1
	blkdiscard -f -v /dev/nvme0n1

	sfdisk /dev/nvme0n1 < nvme0n1.sfdisk

	# format partitions
	mkfs.fat -F 32 /dev/nvme0n1p1
	mkfs.ext4 /dev/nvme0n1p2

	# mount partitions, make swap
	mount /dev/nvme0n1p2 /mnt
	dd if=/dev/zero of=/mnt/swapfile bs=1M count=8192 status=progress
	chmod 0600 /mnt/swapfile
	mkswap -U clear /mnt/swapfile
	swapon /mnt/swapfile
	mount --mkdir /dev/nvme0n1p1 /mnt/boot
else
	exit
fi

read -p "Install Packages? <y/N>: " prompt2
if [ $prompt2 == "y" ]
then
	# install packages
	pacstrap /mnt sudo bash-completion base mkinitcpio kmod iwd \
	linux-tkg-eevdf-generic_v3 linux-tkg-eevdf-generic_v3-headers \
	amd-ucode-git nano linux-firmware-git linux-firmware-whence-git \
	sof-firmware grub efibootmgr tpm2-tss tpm2-tools
	cp /etc/pacman.conf /mnt/etc/ && cp /etc/pacman.d/*-mirrorlist /mnt/etc/pacman.d/

	#generate fs table
	genfstab -U /mnt >> /mnt/etc/fstab
	sed 's/relatime/noatime/g' -i /mnt/etc/fstab
else
	exit
fi

cat <<EOF > /mnt/immediate-post.sh
echo "running passwd for root..."
passwd
useradd -m bedant
echo "running passwd for user..."
passwd bedant
echo 'bedant  ALL=(ALL:ALL) ALL' >> /etc/sudoers
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc
echo "# added english locale for gen
en_US.UTF-8 UTF-8
" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "craptop" > /etc/hostname
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch
pacman -Syu noto-fonts noto-fonts-emoji noto-fonts-cjk plasma-nm spectacle \\
	plasma-desktop plasma-wayland-session plasma-pa powerdevil nvidia-prime \\
	kate bluedevil kscreen dolphin gwenview konsole ark sddm-kcm \\
	wireplumber pipewire pipewire-pulse pipewire-alsa gamescope \\
	pipewire-jack chromium-wayland-vaapi mesa libva-mesa-driver libva \\
	nvidia-dkms power-profiles-daemon libva-utils mesa-utils ffmpeg \\
	vulkan-icd-loader vulkan-tools vulkan-radeon usbutils gamemode

# use iwd as networkmanager backend
echo "[device]
wifi.backend=iwd
" > /etc/NetworkManager/conf.d/wifi_backend.conf

# enable runtime D3 support from the module
echo options nvidia \"NVreg_DynamicPowerManagement=0x02\" > /etc/modprobe.d/nvidia.conf

# power saving for intel wifi cards
echo "options iwlwifi power_save=1" > /etc/modprobe.d/iwlwifi.conf
echo "options iwlmvm power_scheme=3" > /etc/modprobe.d/iwlmvm.conf

# ntfs3 fix
echo SUBSYSTEM==\"block\", ENV{ID_FS_TYPE}==\"ntfs\", ENV{ID_FS_TYPE}=\"ntfs3\" > /etc/udev/rules.d/ntfs3_by_default.rules

# enable PCI power management
echo SUBSYSTEM==\"pci\", ATTR{power/control}=\"auto\" > /etc/udev/rules.d/80-nvidia-pm.rules

# misc
echo "--ozone-platform-hint=auto
--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,OverlayScrollbar
--disable-features=UseChromeOSDirectVideoDecoder
" >> /etc/chromium-flags.conf

# nvidia shader cache persistence fix
echo "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1" >> /etc/environment

# nvidia d3cold workaround: elegant edition: i swear this works now (believe me i was the dgpu)
mv /usr/share/glvnd/egl_vendor.d/10_nvidia.json /usr/share/glvnd/egl_vendor.d/99_nvidia.json
rm -f /usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf
echo "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json" >> /etc/environment
echo "KWIN_DRM_DEVICES=/dev/dri/card0" >> /etc/environment
echo "KWIN_DRM_NO_AMS=1" >> /etc/environment

# firefox wayland env var
echo "MOZ_ENABLE_WAYLAND=1" >> /etc/environment

# disable watchdogs
echo "blacklist sp5100_tco" > /etc/modprobe.d/disable-sp5100-watchdog.conf

echo "<driconf>
   <device>
       <application name="Default">
           <option name="vblank_mode" value="0" />
       </application>
   </device>
</driconf>
" > /etc/drirc

echo ACTION==\"add\|change\", SUBSYSTEM==\"block\", ATTR{queue/rotational}==\"0\", KERNEL==\"nvme?n?\", ATTR{queue/scheduler}=\"none\" > /etc/udev/rules.d/60-iosched.rules

# disable bluetooth
systemctl enable bluetooth.service
sed 's/#AutoEnable=true/AutoEnable=false/' -i /etc/bluetooth/main.conf

# bootloader settings
sed -i -e 's/quiet/quiet mitigations=off pcie_aspm=force nmi_watchdog=0 nowatchdog/' /etc/default/grub
sed -i -e 's/nvidia-drm.modeset=1//g' /etc/default/grub && grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable sddm.service
systemctl disable avahi-daemon.socket
systemctl disable avahi-daemon.service
systemctl mask avahi-daemon.socket
# we're using iwd
systemctl disable wpa_supplicant.service
systemctl mask wpa_supplicant.service
systemctl enable NetworkManager.service
EOF

chmod +x /mnt/immediate-post.sh

read -p "Chroot and run post-script? <y/N>: " prompt3
if [ $prompt3 == "y" ]
then
	# chroot to new system and call the post install script lol
	arch-chroot /mnt /immediate-post.sh
else
	exit
fi

# clean up and unmount
rm -rf /mnt/immediate-post.sh
swapoff -a
umount /dev/nvme0n1p1
umount /dev/nvme0n1p2
