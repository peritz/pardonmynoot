---
title: "Cyber Security Workstation Setup (Part 1)"
slug: securesetup-01
date: 2024-02-24T13:01:32Z
image: /images/hacker-cover.jpg
tags:
  - cybersecurity
  - linux
  - securesetup
showTableOfContents: true
type: post
draft: false
---

{{< figure src="/images/hacker-cover.jpg" caption="Photo by Kevin Horvat on Unsplash " alt="Hooded figure working at multiple monitors with code and terminals on each." >}}

> Disclaimer: This is a technical post, so if you're not particularly interested in the technical side of things then this is your warning 🙂

# Cyber Generalism

I'm sure many can relate to the idea of being a cyber generalist. There's many jobs out there that call for someone to understand at a surface level a great deal about how to do things on computers. I did a Computer Science degree with no particular focus, and started my career in penetration testing (ethical hacking to my friends). I've since moved into an engineering team lead role in a CTI department, which requires a great deal of different cyber skills. I'm still the defacto pentester for our team, as well as dealing with traditional DevOps and cloud technologies. I do scripting for various CTI teams and am also expected to understand how to deploy, maintain, and secure technologies ranging from kubernetes clusters to traditional on-prem LAMP stacks.

I've had a journey that has seen my preference for OS change drastically from being a hardcore Windows supporter (large customisation of my machine via PowerShell), to an avid fan of Apple (everything just works), and finally settling on Linux in various shades. In work the standard has been to use Windows, and there are a tonne of internal tools for hardening it and customising it to fit our needs. We used VMs for things like Kali and any Linux distros we needed for our day-to-day testing, but many people did lots of their work inside Windows.

This just doesn't work for me any more. There's only so far you get can with Windows Subsystem for Linux and using VMs on a Windows machine for all your work feels backwards (Windows takes more resources than my VMs but I do all my work in VMs? Doesn't make sense). I reached out to a few colleagues elsewhere in the business who do general cyber-stuff and they had come up with an interesting solution. They conduct all their work inside VMs, running on lightweight base OSes, and network them in such a way as to segregate their responsibilities. These are people who conduct CTI operations on the likes of Tor and need to keep OpSec strong. They also do a lot of malware reversing which brings a whole host of risks. Some of this they do on the same machine as their corporate access, so you can imagine the risks they need to consider.

Their solution I want to create looks something like the following:

{{< figure src="/images/securesetup-vyos.png" caption="Secure setup using VyOS as a software router" alt="Diagram depicting the networking setup for my workstation using VyOS as a software router routing traffic from multiple interfaces via a firewall and a series of VPNs depending on the intended destination of traffic" >}}

There are multiple VPNs running inside a router VM (VyOS in this case). All machines get routed through a firewall prior to the VPNs, and the corporate ones get routed through a proxy which limits the domains that can be connected to. Our corporate VPN is a Cisco AnyConnect VPN, which isn't available as a client on VyOS, so we create another VM running the client and push all corporate traffic through that. All the other VPNs are OpenVPN and can be added as interfaces in VyOS.

I also do some HackTheBox in my spare time, which is why there is a HTB VPN and dedicated VM. Additionally, we have resources deployed in AWS that we access via a VPN, so this is another network connection.

Each VPN network is assigned it's own virtual network which machines connect to and have their traffic routed accordingly. Altogether we separate our concerns appropriately and are able to conduct a variety of activities on one machine with a minimal amount of risk.

Through this and subsequent posts I will describe in detail how I installed this setup on my work machine (a beefy Dell laptop with 64GB of RAM, a NVIDIA graphics card, and an Intel 12th Gen i7 processor).

This post will cover the initial installation of the operating system on the base machine, as well as connecting it to the network and installing QEMU and libvirt for virtualisation. Subsequent posts will cover the virtual networking setup needed and the installation of VPNs and virtual machines for work.

# Base OS Selection

I chose Arch Linux as my base operating system and activated KVM as the hypervisor. KVM is ideal for me since all my work will be conducted in VMs, and KVM essentially transforms the Linux kernel into a hypervisor. There are some helpful utilities installed which allow me to browser the web, access a UI, and various other things that will be necessary to install our VMs. Once everything is set up I can remove most of the bloat and keep the base OS as slim as possible.

Why Arch Linux? I'm fond of the involvement it requires to get things running. It is a very slim OS to begin with and you can limit your software to only what is needed to get a job done. The less that is installed on my base and the less resources it uses the better, as it allows me to allocate more to my VMs. Additionally, it has a rolling updates system which I prefer over the distribution versions used in Debian-derivatives. I'm not familiar enough with other UNIX distributions to have considered them, but Arch Linux has given me exactly what I want in the past.

Note that the selection of Arch is a personal preference, since KVM is included in most mainline distros within the kernel.

Let's get into the install process.

# Installation

> More information about this process can be found at the Arch Linux wiki: https://wiki.archlinux.org/title/Installation_guide

Navigate to https://archlinux.org/download/ and download from one of the mirrors. Verify it against the SHA256 signature. If you are concerned about the safety of your network, then also check it against the PGP signature. This is done by downloading the signature file and running:

```sh
gpg --keyserver-options auto-key-retrieve --verify archlinux-_version_-x86_64.iso.sig
```

Using Balena Etcher flash the ISO image to a USB stick. Disable secure boot and enable USB boot support in your BIOS settings, then reboot in to the live install environment.

We're going to be running with [dm-crypt on top of LVM](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS). This is the easiest method for allowing suspension to disk and is what I've used before on previous Linux installations.

Once we have booted into the live installation medium, we can perform the following install:

```sh
localectl list-keymaps
loadkeys uk

# Verify 64-bit or 32-bit
cat /sys/firmware/efi/fw_platform_size

# Enter a tmux pane to make scrollback a bit easier with C-b PPage
tmux

# Connect to wifi
iwctl
station list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect <network>

# Verify
ping archlinux.org

# Update clock
timedatectl

# Now partition disk - for us we use our secondary nvme - nvme1n1
gdisk /dev/nvme1n1
o # create new GUID partition table
n # New partition of type EF00 and size 512MB
n # New partition of type 8309 and remainder of size
p # Print table to verify
w # Write and exit

# Encrypt drives now
# Create the container - use pbkdf2 for GRUB2 compatibility:
# https://wiki.archlinux.org/title/GRUB#LUKS2
# https://savannah.gnu.org/bugs/?55093
cryptsetup luksFormat --pbkdf pbkdf2 /dev/nvme1n1p2

# Open the container
cryptsetup open /dev/nvme1n1p2 cryptlvm

# Create a physical volume on top of the opened drive
pvcreate /dev/mapper/cryptlvm

# create the volume group and volumes
vgcreate VolGroup /dev/mapper/cryptlvm
lvcreate -L 72G VolGroup -n swap # RAM + sqroot(RAM) for hibernation
lvCreate -l 100%FREE VolGroup -n root # Likely don't need separate paritions outside of HOME

# Format the filesystems
mkfs.ext4 /dev/VolGroup/root
mkfs.fat -F 32 /dev/nvme1n1p1
mkswap /dev/VolGroup/swap

echo "Worth a note here that you should make a note of the UUIDs of your disks"
echo "Otherwise, use `ls -l /dev/disk/by-uuid/` later on"

# Mount
mount /dev/VolGroup/root /mnt
swapon /dev/VolGroup/swap

# EFI partition
mkdir /mnt/efi
mount /dev/nvme1n1p1 /mnt/efi

# Chroot in
pacstrap /mnt base linux-hardened linux-firmware util-linux vim grep grub efibootmgr man-db man-pages texinfo e2fsprogs exfatprogs networkmanager lvm2 inetutils

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt
```

Note that I have opted for the `linux-hardened` kernel which adds numerous security enhancements on top of the normal kernel. This is a personal selection made as the result of the environment in which I work.

# System boot configuration

We need to take several steps before we can actually boot into this system

First, create an extra keyfile so that GRUB doesn't ask for a password twice

```sh
dd bs=512 count=4 if=/dev/random of=/root/cryptlvm.keyfile iflag=fullblock
chmod 000 /root/cryptlvm.keyfile
cryptsetup -v luksAddKey /dev/nvme1n1p2 /root/cryptlvm.keyfile
```

Next, we need to install the intel microcode to mitigate hardware exploits, and then configure the initramfs (initial RAM filesystem):

```sh
pacman -S intel-ucode
```

edit the following in /etc/mkinitcpio.conf:

```
FILES=(/root/cryptlvm.keyfile)

HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck)
```

Then install the initramfs:

```sh
mkinitcpio -P

# Protect keyfile
chmod 600 /boot/initramfs-linux*
```

For now, let's continue with some essential configuration:

```sh
ln -sf /usr/share/zoneinfo/GB /etc/localtime

hwclock --systohc
```

Uncomment `en_GB.UTF-8 UTF-8` from `/etc/locale.gen` then run:

```sh
locale-gen
```

Edit `/etc/locale.conf` with `LANG=en_GB.UTF-8` and `/etc/vconsole.conf` with `KEYMAP=uk`

Create a hostname in `/etc/hostname`.

Set a root password with `passwd` and then install the bootloader:

Check that your SSD supports TRIM using `lsblk --discards`. If not then omit the `allow-discards` option from the following GRUB config. Edit `/etc/default/grub`:

```
GRUB_ENABLE_CRYPTODISK=y

GRUB_CMDLINE_LINUX=". . . cryptdevice=UUID=deviceuuid:cryptlvm:allow-discards cryptkey=rootfs:/root/cryptlvm.keyfile resume=/dev/VolGroup/swap"

GRUB_PRELOAD_MODULES="part_gpt part_msdos lvm"
```

If you wrote the above literally then you will need to get the UUID of the disk:

```sh
uuid=$(ls -al /dev/disk/by-uuid | grep nvme1n1p2 | awk '{ print $9 }')
sed -i "s/deviceuuid/$uuid/" /etc/default/grub
```

Cat the `/etc/default/grub` file to double check this worked.

Now install GRUB:

```sh
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck

grub-mkconfig -o /boot/grub/grub.cfg
```

At this point we can reboot and login:

```
Ctrl-D

umount -R /mnt

reboot
```

# Networking

Now that we have booted into our system, we can connect back to wifi (won't be necessary if you're already using ethernet):

```sh
systemctl enable --now NetworkManager
systemctl enable --now wpa_supplicant

nmcli device wifi list
# Don't forget the space below to avoid password ending up in console history
 nmcli device wifi connect BSSID_OR_SSID password <password>
```

# Secure boot configuration

Secure Boot implementations use these keys:

Platform Key (PK)
    Top-level key.
Key Exchange Key (KEK)
    Keys used to sign Signatures Database and Forbidden Signatures Database updates.
Signature Database (db)
    Contains keys and/or hashes of allowed EFI binaries.
Forbidden Signatures Database (dbx)
    Contains keys and/or hashes of deny-listed EFI binaries.

We need at least PK, KEK, and db in order for this to work. First, backup the keys that we have already in the database, maybe to a USB stick UNENCRYPTED so that it can be recovered from the firmware settings:

```sh
pacman -S efitools

for var in PK KEK db dbx ; do efi-readvar -v $var -o old_${var}.esl ; done
```

Before we can go further, we need SecureBoot to be in setup mode. This means the PK must be removed. If required (check output of last command if required) then remove it in the BIOS settings. On my laptop BIOS it was also required to enable the "Custom Mode" from the firmware Boot Configuration settings and run the following:

```sh
chattr -i /sys/firmware/efi/efivars/KEK-UUID
chattr -i /sys/firmware/efi/efivars/db-UUID
```

`sbctl` is a Secure Boot helper utility:

```
pacman -S sbctl
```

Check that we are in Setup Mode:

```
sbctl status
```

Then create our keys and enroll them (alongside Microsoft's)

```
sbctl create-keys

sbctl enroll-keys -m
```

Check with `sbctl status` that it now shows as being installed and Setup Mode as being disabled. Then sign your stuff and re-install grub onto the EFI:

```
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock

sbctl sign -s /boot/vmlinuz-linux-hardened
sbctl sign -s /efi/EFI/GRUB/grubx64.efi
```

Reboot, then boot into firmware settings and enable Secure Boot again.

# General System Configuration

Now that we have a secure boot enabled Linux installation, fully encrypted with swap and all sorts of nice security features, we need to configure the system for our needs. This is probably by far going to be the longest section, as lots of things are needed for this to work.

## Security Configuration

The Arch Linux wiki offers a number of suggestions for hardening a system. First among these is a regular user, rather than root, but who has sudo privileges. This is fine since a password entry is needed to run these commands as root:

```sh
useradd --create-home --user-group consultant
pacman -S sudo

# Uncomment the line beginnning with %wheel which allows anyone belonging
# to the sudo group to run commands as root entering a password. Ensure to
# uncomment the first one, not the second, which allows the same without
# entering a password.
EDITOR=vim sudoedit /etc/sudoers

usermod -aG wheel consultant
passwd consultant
```

There is a discussion here around whether or not this should be done. Really we could disallow the consultant user from accessing sudo altogether, instead opting for `su root` and entering the root password. I feel like this is sufficient though.

Beyond this, read through https://wiki.archlinux.org/title/Security and get an idea of what is needed. You'll run commands to check that everything is in place, and to check the general security for your system. This is what was run in my case:

```sh
# Check if we are vulnerable to known exploits
grep -r . /sys/devices/system/cpu/vulnerabilities

# Ensure that microcode was loaded
journalctl -k --grep=microcode

# Add the following line to /etc/pam.d/system-login
auth optional pam_faildelay.so delay=4000000
```

I have opted not to do the following for my base machine, for performance/usability reasons (but may use with guest VMs):
- hardened_malloc
- filesystem quotas - we're not running a server with logs
- configure `pam_faillock.so` at `/etc/security/faillock.conf` with stricter options
- Edit `/etc/security/limits.conf` with stricter process limits
- Locking root - we maintain for emergencies (could also be achieved with live boot of a linux install medium)
- Edit `/etc/security/access.conf` to control how users are allowed to login, as it is only a local machine for a single user
- AppArmour - at least not for the base machine
- Firewalls on the base machine

Note that because we are using the `linux-hardened` kernel, some drivers that sit outside the main tree need to be substituted by their DKMS equivalents. See the [relevant page](https://wiki.archlinux.org/title/Dynamic_Kernel_Module_Support) on the arch wiki for this.

The `linux-hardened` kernel sets a bunch of security features on by default, such as hardening for BPF and disabling kexec to allow changes to the kernel during runtime.

## Window Manager and Displaying Stuff

We need to now work on actual graphics so we can start creating virtual machines and using them. I've had a number of thoughts on doing this, and considered moving to Wayland for security reasons, but I think this may be more troublesome than it's worth, at least for this part of my career. Instead, I'm opting to use Xorg.

I currently use i3 as my window manager; I'm a big fan of the tiled layout and workspaces. It works well for me since I conduct most of my editing in Neovim and use Tmux to persist sessions and allow me to do multiple activities from one console (which I can later detach and reattach).

I wanted to have each VM occupy my entire screen almost as if it was running on the base system (making the use of a VM totally transparent). After some research, it's becoming apparent that it is not possible to place a VM window created by qemu in it's own dedicated virtual terminal unless I wanted to login multiple times across multiple terminals to do it. This can be done, but I still need to be able to display things. See this answer from [StackExchange](https://unix.stackexchange.com/q/550892):

> You can start another X11 server and run qemu in full screen mode inside it. As root: `startx -- :1; xauth extract - :1 | su USER -c 'xauth merge -'`. Then as USER: `DISPLAY=:1 qemu -full-screen ...`. You can then switch between qemu and your gui screen via ctrl-alt-Fx. This may have problems with the screen resolution adjusment in the guest, but it's a start. qemu/SDL or whatever backend could probably run without an X11 server, but I have no idea how/if accelerated qemu video card emulations like virtio work with it.
> 
> – user313992

To get all the graphics and nice stuff working for our laptop, we need to install relevant drivers for the NVIDIA graphics card we have on board, as well as configuring X11 and a window server to run things on. We'll also install git and a better shell so that we can do some customisation using (my custom) dotfiles:

```sh
pacman -S linux-hardened-headers dkms nvidia-dkms xorg xorg-xinit i3 dmenu git openssh zsh neovim pkgconf rxvt-unicode ttf-anonymous-pro

reboot
```

Now that we've got things installed, let's do some fun configuration (as unprived user) and add key to GitHub before you clone:

```
ssh-keygen -t ed25519 -C "Arch Hypervisor"

mkdir git && cd git
git clone --recurse-submodules git@github.com:peritz/dotfiles.git

cd dotfiles
./install.sh

# For neovim Packer
pacman -S zip unzip python python-virtualenv npm go
```

Now let's install our neovim packages. In neovim:

```
:PackerSync
:Mason
```

When you logout and login again now you'll hopefully find that your configuration causes a window manager to pop up. If not and X starts and then logs you out and there's no error in `/var/log/Xorg.0.log` then it might be your xinitrc has failed to launch anything. Check it to find out.

The brightness keys and audio won't work by default, this is the next thing we need to sort out.

## Audio and Brightness

https://wiki.archlinux.org/title/Backlight provides most of the information required for a backlight. The exact steps I took are as follows:

```sh
# Use brightnessctl since xbacklight wasn't working
sudo pacman -S brightnessctl
```

I put the following in my i3 configuration:

```
set $refresh_i3status killall -SIGUSER1 i3status
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +5% && $refresh_i3status
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%- && $refresh_i3status
```

For sound, we need to install alsa-utils and PulseAudio (makes managing sound a bit easier):

```sh
sudo pacman -S alsa-utils pulseaudio pulseaudio-alsa
```

Now if we run `alsamixer` and press `m` on the channels that show `MM` we should be good to go.

We can install PulseAudio, but I'll avoid that until necessary.

I add the following to my i3 config:

```
bindsym XF86AudioRaiseVolume exec --no-startup-id amixer set Master 5%+ && $refresh_i3status
bindsym XF86AudioLowerVolume exec --no-startup-id amixer set Master 5%- && $refresh_i3status
bindsym XF86AudioMute exec --no-startup-id amixer set Master toggle && $refresh_i3status
```

Make sure that in your i3status config that the volume device is set to `default` if you are using ALSA without PulseAudio. I later installed PulseAudio since hotplugging of devices wasn't working with pure ALSA.

Now things should work :) Onwards and upwards because we have a WM and a shell and we can start installing and running things.

Next steps will be to configure virtual networking and the VMs. Until next time!

---

*If you have any questions, please get in touch at
[peritz@pardonmynoot.com](mailto:peritz@pardonmynoot.com).*
