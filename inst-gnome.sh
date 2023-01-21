#!/bin/bash

echo "[General]
EnableNetworkConfiguration=true
EnableIPv6=true" > /etc/iwd/main.conf
# iwctl station wlan0 connect "SSID"
# echo "sleeping for 5s to connect to wifi"
# sleep 5
# reflector --protocol https,http --latest 10 --country us,de --download-timeout 60 --verbose --sort rate --save /etc/pacman.d/mirrorlist
# cloudfare is a real one for this, may be late to sync tho
echo "Server = https://cloudflaremirrors.com/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
systemctl disable reflector.service
systemctl mask reflector.service
pacman-key --init

# x86-64_v3 binaries from ALHP repos
curl -o alhp-mirrorlist https://git.harting.dev/ALHP/alhp-mirrorlist/raw/branch/master/mirrorlist
cp alhp-mirrorlist /etc/pacman.d/
curl -O https://git.harting.dev/ALHP/alhp-keyring/raw/branch/master/alhp.gpg
echo "downloaded alhp repo files"
sleep 1;
pacman-key -a alhp.gpg
pacman-key --lsign-key 2E3B2B05A332A7DB9019797848998B4039BED1CA
pacman-key --lsign-key 0D4D2FDAF45468F3DDF59BEDE3D0D2CD3952E298
if ! grep -Fq "core-x86-64-v3" /etc/pacman.conf;
then
	sed 's/#VerbosePkgLists/VerbosePkgLists/' -i /etc/pacman.conf
	sed 's/#ParallelDownloads/ParallelDownloads/' -i /etc/pacman.conf
	sed -z 's/default mirrors./default mirrors.\n\n[core-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n[extra-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n[community-x86-64-v3]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist/' -i /etc/pacman.conf
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
	pacstrap /mnt sudo bash-completion base mkinitcpio kmod iwd linux linux-headers amd-ucode nano linux-firmware sof-firmware grub efibootmgr
	cp /etc/pacman.conf /mnt/etc/ && cp /etc/pacman.d/alhp-mirrorlist /mnt/etc/pacman.d/

	#generate fs table
	genfstab -U /mnt >> /mnt/etc/fstab
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
pacman -Syu noto-fonts noto-fonts-emoji noto-fonts-cjk networkmanager gnome-shell gdm gnome-control-center eog nautilus file-roller gnome-text-editor gnome-terminal gnome-calculator gnome-calendar xdg-user-dirs-gtk wireplumber pipewire pipewire-pulse pipewire-alsa pipewire-jack firefox libva-mesa-driver ffmpeg nvidia-dkms power-profiles-daemon tpm2-tss

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
mv /usr/share/glvnd/egl_vendor.d/10_nvidia.json /usr/share/glvnd/egl_vendor.d/99_nvidia.json

# what in the name of all things silicon?
rm -f /usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf

# GNOME wayland force
sed -e '/RUN+="\/usr\/lib\/gdm-runtime-config set daemon PreferredDisplayServer xorg"/ s/^#*/#/' -e '/RUN+="\/usr\/lib\/gdm-runtime-config set daemon WaylandEnable false"/ s/^#*/#/' /usr/lib/udev/rules.d/61-gdm.rules > /etc/udev/rules.d/61-gdm.rules
echo "MOZ_ENABLE_WAYLAND=1" >> /etc/environment
echo "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1" >> /etc/environment

# bootloader settings
sed -i -e 's/quiet/quiet mitigations=off pcie_aspm=force amd_pstate=passive/' /etc/default/grub
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
