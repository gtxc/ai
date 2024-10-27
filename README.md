# Arch Linux Automated Installation Script

This POSIX-compliant shell script automates the installation of Arch Linux on a UEFI system. It configures disk partitions, installs base packages, sets up network and user accounts, and configures the system for first boot. This is intended for advanced users who understand the Arch Linux installation process.

## Features

- Automatic partitioning, formatting, and mounting of the specified disk
- Base Arch Linux installation with additional essential packages
- Microcode detection and installation (Intel or AMD)
- Systemd-boot installation and configuration
- Configures hostname, user account, and network settings
- Enables enhanced `pacman` configurations for color, animations, and parallel downloads
- Logs installation steps and errors for debugging purposes

## Prerequisites

1. **UEFI Boot Mode:** The script only supports UEFI; ensure your system is set to boot in UEFI mode.
2. **Root Access:** The script must be run as root.
3. **Internet Connection:** You’ll need network information for a wireless connection.

## Getting Started

1. **Download the Script**: Clone or download this repository to your live USB or environment.

   ```sh
   curl -LO https://raw.githubusercontent.com/gtxc/ai/master/ai.sh
   ```

2. **Edit Script Variables:** Open the script in a text editor and set values for the following variables:
   
   - `station`: Network interface (e.g., `wlan0`)
   - `ssid` and `passphrase`: Network SSID and passphrase
   - `username` and `password`: New user’s name and password
   - `hostname`: System hostname
   - `disk`: Target disk for installation (e.g., `/dev/sda`)

3. **Run the Script**: Execute directly using `sh` or make the script executable and start the installation.

    ```sh
    sh ai.sh
    ```
    OR
   ```sh
   chmod +x ai.sh
   ./ai.sh
   ```

4. Follow any prompts during installation to confirm disk operations.

## Key Installation Steps

- **User and Boot Mode Verification**: Confirms the script is running as root in UEFI mode.
- **Disk Partitioning and Formatting**: Partitions and formats the target disk for a UEFI Arch installation.
- **Network Configuration**: Attempts to connect to the specified Wi-Fi network and sets the system time.
- **Package Installation**: Installs base packages, kernel, network manager, and basic utilities.
- **Locale and Hostname Configuration**: Sets system locale, timezone, hostname, and network configuration.
- **User Setup**: Configures root and user accounts with sudo permissions.
- **Bootloader**: Sets up `systemd-boot` for boot management.

## Post-Installation

After installation, a `pi.sh` script is saved in the user’s home directory to handle any post-installation steps.

## Logging and Debugging

Set `debug=true` to generate a detailed installation log, saved both in the working directory and the user’s home directory after installation.

## Troubleshooting

Ensure you meet all prerequisites and adjust the script parameters to fit your setup. For any issues during installation, review the generated log file.

## License

This script is open-source and available under the MIT License. Feel free to modify and distribute it as needed.
