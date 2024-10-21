#!/bin/sh

station="wlan0"
ssid=""
passphrase=""
username=""
password=""
hostname="arch"
disk=/dev/sdX
debug=true

main() {
  verify_user
  verify_boot_mode
  check_disk
  check_network
  partition_disk
  format_disk
  mount_fs
  detect_ucode
  base_install
  post_install
  umount_fs
}

verify_user() {
  inf "Verifying user..."
  [ "$(id -u)" -eq 0 ] || die "This script must be run as root."
}

verify_boot_mode() {
  inf "Verifying boot mode: UEFI..."
  [ -d /sys/firmware/efi ] || die "Reboot system in UEFI mode."
}

check_disk() {
  inf "Checking disk ${disk}..."
  [ -z "$disk" ] || [ ! -b "$disk" ] && die "No installable disk found."

  inf "--- Devices ---"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
  ans=no
  get ans "The disk '$disk' will be wiped. Are you sure you want to proceed? (yes/no): "
  [ "$ans" = "yes" ] || die "Process terminated!"
}

check_network() {
  inf "Checking network connection..."
  if ! nc -zw1 archlinux.org 443; then
    inf "Connecting to $ssid through $station..."
    iwctl station "$station" connect "$ssid" --passphrase "$passphrase" || die "Failed to connect. Check network preferences."
  fi
  timedatectl set-ntp true
}

partition_disk() {
  inf "Creating partitions..."
  parted -s $disk mklabel gpt
  parted -sa optimal $disk mkpart primary fat32 0% 1025MiB
  parted -sa optimal $disk mkpart primary linux-swap 1025MiB 9218MiB
  parted -sa optimal $disk mkpart primary ext4 9218MiB 100%
  parted -s $disk set 1 esp on

  inf "Informing the Kernel about the disk changes..."
  partprobe "$disk"
}

format_disk() {
  inf "Formatting partitions..."
  mkfs.fat -IF32 ${disk}1
  mkswap ${disk}2
  echo "y" | mkfs.ext4 ${disk}3
}

mount_fs() {
  inf "Mounting filesystem..."
  mount ${disk}3 /mnt
  mount -m ${disk}1 /mnt/boot
  swapon ${disk}2
}

detect_ucode() {
  inf "Detecting ucode..."
  cpu=$(grep vendor_id /proc/cpuinfo)
  case "$cpu" in
  *AuthenticAMD*)
    inf "An AMD CPU has been detected, the AMD microcode will be installed."
    ucode="amd-ucode"
    ;;
  *GenuineIntel*)
    inf "An Intel CPU has been detected, the Intel microcode will be installed."
    ucode="intel-ucode"
    ;;
  *)
    die "Cannot detect ucode."
    ;;
  esac
}

base_install() {
  inf "Installing base packages..."
  pacstrap -K /mnt base base-devel linux linux-firmware "$ucode" neovim tmux git networkmanager man-db man-pages

  inf "Generating fstab..."
  genfstab -U /mnt >>/mnt/etc/fstab

  inf "Setting timezone..."
  ln -sf "/mnt/usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone)" /mnt/etc/localtime
  arch-chroot /mnt hwclock --systohc

  inf "Setting locale..."
  sed -i "s/#en_US.UTF-8/en_US.UTF-8/g" /mnt/etc/locale.gen
  echo "LANG=en_US.UTF-8" >>/mnt/etc/locale.conf
  arch-chroot /mnt locale-gen

  inf "Configuring hosts, hostname..."
  echo "$hostname" >/mnt/etc/hostname
  cat <<-EOF >>/mnt/etc/hosts
		127.0.0.1 localhost
		::1 localhost
		127.0.1.1 $hostname.localdomain $hostname
	EOF

  inf "Setting root password..."
  printf "%s:%s" "root" "$password" | arch-chroot /mnt chpasswd

  inf "Creating user ${username}..."
  arch-chroot /mnt useradd -m "$username"
  arch-chroot /mnt usermod -aG wheel "$username"
  printf "%s:%s" "$username" "$password" | arch-chroot /mnt chpasswd "$username"

  inf "Setting sudo permissions..."
  echo "%wheel ALL=(ALL) ALL" >/mnt/etc/sudoers.d/00_"$username"

  inf "Setting sudo keep env, pwfeedback..."
  echo "Defaults !env_reset,pwfeedback" >>/mnt/etc/sudoers.d/00_"$username"

  inf "Setting default editor nvim..."
  echo "Defaults editor=/usr/bin/nvim" >>/mnt/etc/sudoers.d/00_"$username"

  inf "Installing systemd-boot..."
  arch-chroot /mnt bootctl --path=/boot install

  inf "Creating and editing systemd-boot loader entry..."
  mkdir -p /mnt/boot/loader
  cat <<-EOF >/mnt/boot/loader/loader.conf
		default arch
		timeout 0
	EOF

  mkdir -p /mnt/boot/loader/entries
  puiid=$(blkid -s PARTUUID -o value ${disk}3)
  cat <<-EOF >/mnt/boot/loader/entries/arch.conf
		title Arch Linux
		linux /vmlinuz-linux
		initrd /$ucode.img
		initrd /initramfs-linux.img
		options root=PARTUUID=$puiid rw rootfstype=ext4
	EOF

  inf "Enabling colors, animations, and parallel downloads for pacman..."
  sed -i "s/^#Color$/Color/" /mnt/etc/pacman.conf
  sed -i "s/^#VerbosePkgLists$/VerbosePkgLists/" /mnt/etc/pacman.conf
  sed -i "/^CheckSpace$/a ILoveCandy" /mnt/etc/pacman.conf
  sed -i "s/^#ParallelDownloads = \([0-9]\+\)$/ParallelDownloads = \1/g" /mnt/etc/pacman.conf

  inf "Enabling/Staring netowrk service..."
  arch-chroot /mnt systemctl enable NetworkManager.service
}

post_install() {
  curl --create-dirs -LO --output-dir /mnt/home/"$username" https://raw.githubusercontent.com/gtxc/di/master/di.sh
  arch-chroot /mnt chown "$username":"$username" /home/"$username"/di.sh
  inf "Installation completed."
  inf "See ~/di.sh for post installation."
}

umount_fs() {
  inf "Unmounting filesystem..."
  umount ${disk}1
  umount ${disk}3
  swap off ${disk}2
}

inf() {
  printf "\033[1m\033[34m:: \033[37m%s\033[0m\n" "$*"
}

err() {
  printf "\033[1m\033[91m:: %s\033[0m\n" "$*" >&2
}

die() {
  err "$*"
  exit 1
}

get() {
  printf "\n\033[1m\033[32m:: \033[37m%s\033[0m" "$2"
  read -r "$1"
}

log() {
  if [ "$debug" = "true" ]; then
    PS4="\033[1m\033[32m=>\033[37m "
    log_file="installation_$(date +%Y%m%d_%H%M%S).log"
    wd="$PWD"
    set -x # -e
    main 2>&1 | tee "$wd"/"$log_file"
    cp "$wd"/"$log_file" /home/"$username"/
    return
  fi
  main
}

log
