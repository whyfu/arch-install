#!/bin/bash

echo "[General]
EnableNetworkConfiguration=true
EnableIPv6=true" > /etc/iwd/main.conf
# iwctl station wlan0 connect "SSID"
# echo "sleeping for 5s to connect to wifi"
# sleep 5
# reflector --protocol https,http --latest 10 --country us,de --download-timeout 60 --verbose --sort rate --save /etc/pacman.d/mirrorlist

echo "Server = https://mirrors.rit.edu/archlinux/\$repo/os/\$arch
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
Server = http://mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = http://phinau.de/arch/\$repo/os/\$arch
Server = https://phinau.de/arch/\$repo/os/\$arch
Server = https://cloudflaremirrors.com/archlinux/\$repo/os/\$arch
" > /etc/pacman.d/mirrorlist
echo "Server = https://de-mirror.chaotic.cx/\$repo/\$arch
Server = https://de-2-mirror.chaotic.cx/\$repo/\$arch
Server = https://de-3-mirror.chaotic.cx/\$repo/\$arch
Server = https://de-4-mirror.chaotic.cx/\$repo/\$arch
Server = https://in-mirror.chaotic.cx/\$repo/\$arch
Server = https://in-2-mirror.chaotic.cx/\$repo/\$arch
Server = https://in-3-mirror.chaotic.cx/\$repo/\$arch
" > /etc/pacman.d/chaotic-mirrorlist

systemctl disable reflector.service
systemctl mask reflector.service
pacman-key --init

# x86-64_v3 binaries from ALHP repos
curl -o alhp-mirrorlist https://somegit.dev/ALHP/alhp-mirrorlist/raw/branch/master/mirrorlist
cp alhp-mirrorlist /etc/pacman.d/
curl -O https://somegit.dev/ALHP/alhp-keyring/raw/branch/master/alhp.gpg
curl -O https://raw.githubusercontent.com/chaotic-aur/keyring/master/chaotic.gpg
echo "downloaded alhp repo files"
sleep 1;
pacman-key -a alhp.gpg
pacman-key --lsign-key 2E3B2B05A332A7DB9019797848998B4039BED1CA
pacman-key --lsign-key 0D4D2FDAF45468F3DDF59BEDE3D0D2CD3952E298

# chaotic aur repo keys
pacman-key -a chaotic.gpg
pacman-key --lsign-key EF925EA60F33D0CB85C44AD13056513887B78AEB
pacman-key --lsign-key 1949E60D299007430C94DC0657F3D9CC660431DD
pacman-key --lsign-key 3C3BE09E904072467EFEF0A395A6D49D0BBD2A8B
pacman-key --lsign-key A3873AB27021C5DD39E0501AFBA220DFC880C036
pacman-key --lsign-key 1F0716DC94015CAC77FA65B619A2282AFCA8A81E
pacman-key --lsign-key 67BF8CA6DA181643C9723B4ED6C9442437365605

if ! grep -Fq "core-x86-64-v3" /etc/pacman.conf;
then
	sed 's/#VerbosePkgLists/VerbosePkgLists/' -i /etc/pacman.conf
	sed 's/#ParallelDownloads/ParallelDownloads/' -i /etc/pacman.conf
	sed -z 's/#\[multilib\]\n#/[multilib]\n/' -i /etc/pacman.conf
	sed -z 's/default mirrors./default mirrors.\n\n[core-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n[extra-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n[community-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist/' -i /etc/pacman.conf
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
	dd if=/dev/zero of=/mnt/swapfile bs=1M count=4096 status=progress
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
	linux-tkg-bmq-generic_v3 linux-tkg-bmq-generic_v3-headers \
	amd-ucode-git nano linux-firmware-git linux-firmware-whence-git \
	sof-firmware grub efibootmgr tpm2-tss
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
systemctl disable reflector.service
systemctl mask reflector.service
pacman -Syu noto-fonts noto-fonts-emoji noto-fonts-cjk networkmanager \\
	gnome-shell gdm gnome-control-center eog nautilus file-roller \\
	gnome-text-editor gnome-terminal gnome-calculator gnome-calendar \\
	xdg-user-dirs-gtk wireplumber pipewire pipewire-pulse pipewire-alsa \\
	pipewire-jack chromium-wayland-vaapi mesa-tkg-git libva-mesa-driver libva ffmpeg \\
	nvidia-dkms power-profiles-daemon libva-utils mesa-utils \\
	vulkan-icd-loader vulkan-tools vulkan-radeon usbutils gamemode gamescope \\
	arc-gtk-theme

# use iwd as networkmanager backend
echo "[device]
wifi.backend=iwd
" > /etc/NetworkManager/conf.d/wifi_backend.conf

# enable amd-pstate driver
echo "blacklist acpi_cpufreq" > /etc/modprobe.d/amd-pstate.conf

# enable runtime D3 support from the module
echo options nvidia \"NVreg_DynamicPowerManagement=0x02\" > /etc/modprobe.d/nvidia.conf

# power saving for intel wifi cards
echo "options iwlwifi power_save=1" > /etc/modprobe.d/iwlwifi.conf
echo "options iwlmvm power_scheme=3" > /etc/modprobe.d/iwlmvm.conf

# ntfs3 fix
echo SUBSYSTEM==\"block\", ENV{ID_FS_TYPE}==\"ntfs\", ENV{ID_FS_TYPE}=\"ntfs3\" > /etc/udev/rules.d/ntfs3_by_default.rules

# enable PCI power management
echo SUBSYSTEM==\"pci\", ATTR{power/control}=\"auto\" > /etc/udev/rules.d/80-nvidia-pm.rules

# glvnd stuff
mv /usr/share/glvnd/egl_vendor.d/10_nvidia.json ~/Downloads/

# what in the name of all things silicon?
mv /usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf ~/Downloads/

# GNOME wayland force
sed -e '/RUN+="\/usr\/lib\/gdm-runtime-config set daemon PreferredDisplayServer xorg"/ s/^#*/#/' -e '/RUN+="\/usr\/lib\/gdm-runtime-config set daemon WaylandEnable false"/ s/^#*/#/' /usr/lib/udev/rules.d/61-gdm.rules > /etc/udev/rules.d/61-gdm.rules

# misc
echo "--ozone-platform=wayland
--enable-features=VaapiVideoDecoder
--enable-features=VaapiIgnoreDriverChecks
--disable-features=UseChromeOSDirectVideoDecoder
" >> /etc/chromium-flags.conf
echo "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1" >> /etc/environment
echo "blacklist sp5100_tco" > /etc/modprobe.d/disable-sp5100-watchdog.conf
echo "<driconf>
   <device>
       <application name="Default">
           <option name="vblank_mode" value="0" />
       </application>
   </device>
</driconf>
" > /etc/drirc

echo ACTION==\"add\|change\", SUBSYSTEM==\"block\", ATTR{queue/rotational}==\"0\", KERNEL==\"nvme?n?\", ATTR{queue/scheduler}=\"kyber\" > /etc/udev/rules.d/60-iosched.rules

# disable bluetooth
systemctl enable bluetooth.service
sed 's/#AutoEnable=true/AutoEnable=false/' -i /etc/bluetooth/main.conf

# bootloader settings
sed -i -e 's/quiet/quiet mitigations=off pcie_aspm=force amd_pstate=active nmi_watchdog=0 nowatchdog/' /etc/default/grub
sed -i -e 's/nvidia-drm.modeset=1//g' /etc/default/grub && grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable gdm.service
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
