#!/usr/bin/env sh

station="wlan0"
ssid=""
passphrase=""
username=""
password=""
hostname="arch"
disk=/dev/sdX
debug=false

main() {
  verifyuser
  verifybootmode
  checkdisk
  checknetwork
  partitiondisk
  formatdisk
  mountfs
  detectucode
  baseinstall
  postinstall
  umountfs
}

verifyuser() {
  inf "Verifying user..."
  [ "$(id -u)" -eq 0 ] || die "This script must be run as root."
  echo "$username" | grep -qE "^[a-z_][a-z0-9_-]*$" || die "Username '$username' is not valid."
}

verifybootmode() {
  inf "Verifying boot mode: UEFI..."
  [ -d /sys/firmware/efi ] || die "Reboot system in UEFI mode."
}

checkdisk() {
  inf "Checking disk '$disk'..."
  [ -z "$disk" ] || [ -b "$disk" ] || die "No installable disk found."

  inf "--- Devices ---"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
  ans=no
  get ans "The disk '$disk' will be wiped. Are you sure you want to proceed? (yes): "
  [ "$ans" = "yes" ] || die "Process terminated!"
}

checknetwork() {
  inf "Checking network connection..."
  if ! nc -zw1 archlinux.org 443; then
    inf "Connecting to '$ssid' through '$station'..."
    iwctl station "$station" connect "$ssid" --passphrase "$passphrase" || die "Failed to connect. Check network preferences."
  fi
  timedatectl set-ntp true
}

partitiondisk() {
  inf "Creating partitions..."
  parted -s "$disk" mklabel gpt
  parted -sa optimal "$disk" mkpart primary fat32 0% 1025MiB
  parted -sa optimal "$disk" mkpart primary linux-swap 1025MiB 9218MiB
  parted -sa optimal "$disk" mkpart primary ext4 9218MiB 100%
  parted -s "$disk" set 1 esp on

  inf "Informing the Kernel about the disk changes..."
  partprobe "$disk"
}

ONE="1"
TWO="2"
THREE="3"

formatdisk() {
  if echo "$disk" | grep -qE "/dev/nvme"; then
    ONE="p1"
    TWO="p2"
    THREE="p3"
  fi
  inf "Formatting partitions..."
  mkfs.fat -IF32 "$disk$ONE"
  mkswap "$disk$TWO"
  echo "y" | mkfs.ext4 "$disk$THREE"
}

mountfs() {
  inf "Mounting filesystem..."
  mount "$disk$THREE" /mnt
  mount -m "$disk$ONE" /mnt/boot
  swapon "$disk$TWO"
}

detectucode() {
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

baseinstall() {
  inf "Installing base packages..."
  pacstrap -K /mnt base base-devel linux linux-firmware "$ucode" dash neovim tmux git networkmanager man-db man-pages

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

  inf "Creating user '${username}'..."
  arch-chroot /mnt useradd -m "$username"
  arch-chroot /mnt usermod -aG wheel "$username"
  printf "%s:%s" "$username" "$password" | arch-chroot /mnt chpasswd "$username"

  inf "Setting sudo permissions..."
  echo "%wheel ALL=(ALL) ALL" >/mnt/etc/sudoers.d/00"$username"

  inf "Setting pwfeedback..."
  echo "Defaults pwfeedback" >>/mnt/etc/sudoers.d/00"$username"

  inf "Installing systemd-boot..."
  arch-chroot /mnt bootctl --path=/boot install

  inf "Enabling all cores to use for compilation..."
  sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

  inf "Disabling makepkg compression..."
  sed -i "/# PKGEXT=/a PKGEXT='.pkg.tar'" /etc/makepkg.conf
  sed -i "/# SRCEXT=/a SRCEXT='.src.tar'" /etc/makepkg.conf

  inf "Creating and editing systemd-boot loader entry..."
  mkdir -p /mnt/boot/loader
  cat <<-EOF >/mnt/boot/loader/loader.conf
		default arch
		timeout 0
	EOF

  mkdir -p /mnt/boot/loader/entries
  puiid=$(blkid -s PARTUUID -o value "$disk$THREE")
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

postinstall() {
  curl --create-dirs -LO --output-dir /mnt/home/"$username" https://raw.githubusercontent.com/gtxc/pi/master/pi.sh
  arch-chroot /mnt chown "$username":"$username" /home/"$username"/di.sh
  inf "Installation completed."
  inf "See ~/pi.sh for post installation."
}

umountfs() {
  inf "Unmounting filesystem..."
  umount "$disk$ONE"
  umount "$disk$THREE"
  swap off "$disk$TWO"
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
    logfile="installation_$(date +%Y%m%d_%H%M%S).log"
    wd="$PWD"
    set -x # -e
    main 2>&1 | tee "$wd"/"$logfile"
    cp "$wd"/"$logfile" /home/"$username"/
    inf "See $wd/$logfile or ~/$logfile for installation logs."
    return
  fi
  main
}

log
