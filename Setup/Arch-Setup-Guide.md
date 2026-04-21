# Arch Linux + Omarchy-Style Desktop — Full Setup Guide

A complete, opinionated guide to installing Arch Linux with an Omarchy-inspired Hyprland desktop, tuned to be friendly for both keyboard and mouse use. Written for a fresh home desktop install.

---

## 0. Strategy (read this first)

Omarchy is DHH's opinionated Arch + Hyprland distro. It's polished but aggressively keyboard-driven. Instead of rebuilding it from scratch, we will:

1. Install a clean, encrypted **Arch Linux** base.
2. Layer **Omarchy** on top (it's a script that configures Hyprland, Waybar, themes, etc.).
3. Apply a set of **mouse-friendly tweaks**: a dock, clickable Waybar, mouse drag-to-move/resize, a GUI file manager, window title bars, Alt-Tab, right-click behavior.

Why this path: Omarchy is actively maintained, well-tested, has a built-in theme system and package helpers. Customizing it is easier than recreating it.

An **Appendix A** at the end shows the fully manual path (Arch + Hyprland from scratch) if you'd rather not layer Omarchy on top.

**Time budget:** Plan ~2 hours for a smooth install. Give yourself a Saturday afternoon for a first-timer.

---

## 1. Before You Begin

### Hardware checklist
- **x86_64 CPU**, UEFI firmware (any desktop from the last ~10 years).
- **≥ 8 GB RAM** (16 GB+ recommended for dev work).
- **≥ 40 GB free disk** on the target drive (preferably an SSD/NVMe).
- **Ethernet cable** if possible — installing over Wi-Fi works but ethernet is zero fuss.
- A **USB stick** (≥ 4 GB) you don't mind wiping.
- A **second device** (phone/laptop) to read this guide while you install.

### Back up anything important on the target drive
The disk you install to will be wiped. Copy anything you need off it now.

### Decide on dual-boot vs. single-boot
Single-boot (Arch only) is simpler and this guide assumes it. If you want to keep Windows alongside, stop and read the Arch Wiki's [dual boot page](https://wiki.archlinux.org/title/Dual_boot_with_Windows) first — Omarchy is designed around full-disk encryption, which complicates dual boot.

### Note your BIOS hotkeys
- Boot menu (usually F12, F10, F8, or ESC at startup).
- BIOS setup (usually DEL or F2).

### In BIOS, before install:
- Enable **UEFI** mode (disable CSM/Legacy).
- Disable **Secure Boot** (you can re-enable later with custom keys; skip for now).
- Enable **XMP/DOCP** for your RAM if you haven't.
- Make sure the target disk is visible.

---

## 2. Create the Bootable USB

### Download the Arch ISO
Grab the latest ISO from https://archlinux.org/download/. Since you're in Australia, the AARNet or Internode mirrors will be fastest:
- https://mirror.aarnet.edu.au/pub/archlinux/iso/latest/
- https://mirror.internode.on.net/pub/archlinux/iso/latest/

Verify the signature if you're being careful — instructions are on the download page.

### Flash the USB
- **From Windows:** use [Rufus](https://rufus.ie/) in "DD image" mode, or [balenaEtcher](https://www.balena.io/etcher/).
- **From Linux/macOS:** `sudo dd if=archlinux-*.iso of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress` (replace `/dev/sdX` with your USB device — `lsblk` to find it).
- **Cross-platform with a reusable stick:** [Ventoy](https://www.ventoy.net/) lets you drop multiple ISOs on the same USB.

### Boot from the USB
Plug it in, boot, hit your boot-menu key, pick the USB. Choose the first entry on the Arch boot menu ("Arch Linux install medium"). You'll land at a root shell.

---

## 3. Install the Arch Base with `archinstall`

Omarchy has its own installer but we'll use vanilla Arch first so you understand your system and can always peel Omarchy off later if you want.

### 3.1 Set keyboard & verify you're in UEFI mode
```bash
loadkeys us                        # skip if your keyboard is already US
ls /sys/firmware/efi/efivars       # if this lists files, you're in UEFI. Good.
```

If that directory is empty, reboot and fix UEFI in BIOS.

### 3.2 Connect to the internet
Ethernet should just work. For Wi-Fi:
```bash
iwctl
# inside iwctl:
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "Your SSID"
exit
```
Test:
```bash
ping -c 3 archlinux.org
```

### 3.3 Sync the clock
```bash
timedatectl set-ntp true
```

### 3.4 Update mirrors for Australia
This makes `pacstrap` dramatically faster:
```bash
reflector --country Australia,"New Zealand" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

### 3.5 Launch archinstall
```bash
archinstall
```

Set these values (leave everything else default unless noted):

| Option | Value |
|---|---|
| **Archinstall language** | English |
| **Keyboard layout** | us (or your layout) |
| **Mirrors and repositories** | Australia (and New Zealand if you want redundancy) |
| **Locales** | `en_AU.UTF-8` (or `en_US.UTF-8`), keymap `us` |
| **Disk configuration** | "Partitioning" → "Use a best-effort default partition layout" → pick your target disk |
| **Disk encryption** | **Enable LUKS**, pick a strong passphrase. Encrypt the root partition. |
| **Filesystem** | **btrfs**, enable subvolumes (for Timeshift/snapshots later) |
| **Swap** | Enable (zram is fine) |
| **Bootloader** | **systemd-boot** (simplest) or **GRUB** (needed if you want encrypted `/boot`) |
| **Hostname** | something like `archbox` |
| **Root password** | leave blank (disables root login — we'll use sudo) |
| **User account** | create your user, add to `wheel` group, set as superuser |
| **Profile** | **Minimal** — do **not** pick a desktop profile; Omarchy will handle that |
| **Audio** | **pipewire** |
| **Kernels** | `linux` (add `linux-lts` as a safety net if you want) |
| **Network configuration** | **NetworkManager** |
| **Timezone** | Australia/Sydney |
| **Automatic time sync (NTP)** | yes |
| **Additional packages** | add: `base-devel git vim sudo openssh reflector btrfs-progs` |

Pick "Install", confirm, let it run. When it asks "Do you want to chroot into the newly created installation?" — say **yes**.

### 3.6 Inside the chroot, quick sanity setup
```bash
# Make sure sudo works for wheel group
EDITOR=vim visudo
# uncomment: %wheel ALL=(ALL:ALL) ALL

# Enable services you'll want
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
systemctl enable fstrim.timer    # SSD trim weekly
```

Exit, unmount, reboot:
```bash
exit
umount -R /mnt
reboot
```

**Remove the USB** as the machine restarts.

---

## 4. First Boot — Finalize the Base

You should hit the LUKS passphrase prompt, then log into a bare TTY as your user.

### 4.1 Confirm networking
```bash
ping -c 3 archlinux.org
# If Wi-Fi: nmtui
```

### 4.2 Install an AUR helper (`yay`)
```bash
sudo pacman -Syu --needed git base-devel
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
cd .. && rm -rf yay-bin
```

### 4.3 Enable multilib (for Steam, Wine, etc. later)
```bash
sudo vim /etc/pacman.conf
# Uncomment these two lines:
# [multilib]
# Include = /etc/pacman.d/mirrorlist
sudo pacman -Syu
```

### 4.4 Install graphics drivers
Pick **one** block based on your GPU. Check with `lspci | grep -Ei 'vga|3d'`.

**Intel iGPU:**
```bash
sudo pacman -S --needed mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver
```

**AMD GPU:**
```bash
sudo pacman -S --needed mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau
```

**NVIDIA (proprietary, recommended for recent cards):**
```bash
sudo pacman -S --needed nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings linux-headers
# Enable early KMS
sudo vim /etc/mkinitcpio.conf
# Change MODULES=() to: MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
sudo mkinitcpio -P
# Enable DRM modeset (required for Hyprland/Wayland)
sudo vim /etc/default/grub   # or /boot/loader/entries/arch.conf for systemd-boot
# Add nvidia_drm.modeset=1 to kernel params
# Regenerate bootloader config if using GRUB: sudo grub-mkconfig -o /boot/grub/grub.cfg
```
NVIDIA on Wayland is noticeably better than it was two years ago, but still the roughest of the three paths. If you have an older card consider the open `nouveau` driver or swapping the card.

Reboot:
```bash
sudo reboot
```

---

## 5. Install Omarchy

Omarchy installs itself as a layer on top of Arch — it clones its repo, adds its package repository, installs Hyprland and its curated package set, and drops in configs.

Back at the TTY, as your normal user:
```bash
cd ~
wget -qO- https://omarchy.org/install | bash
```

(That's Omarchy's official one-line installer. It will ask a few questions — full name, email for Git, a couple of theme choices.)

It'll take a while — it downloads a few hundred packages. When it finishes it reboots into Hyprland.

### After first login
You'll land in Hyprland with the Omarchy welcome wallpaper. Press `Super + Alt + Space` to open the **Omarchy menu** — this is your central hub for installing software, switching themes, and configuring things.

Walk through:
- **Setup → Identification** to check your user info.
- **Style → Theme** to pick a theme you like (there are ~10 built in).
- **Install → Browser** to add Firefox or Brave if you want one.
- **Setup → Display** to arrange monitors.

Take a few minutes to read through the menu — most of what people struggle to configure manually on a vanilla Hyprland install is already a menu entry here.

---

## 6. Mouse-Friendly Customizations

This is the main reason you're reading this guide. Omarchy out of the box is very keyboard-centric. The changes below bring back the mouse affordances without giving up the aesthetic.

> All configs live in `~/.config/`. Back up Omarchy's originals before editing:
> ```bash
> cp -r ~/.config/hypr ~/.config/hypr.bak
> cp -r ~/.config/waybar ~/.config/waybar.bak
> ```

### 6.1 Mouse drag to move/resize windows

Omarchy already sets this, but confirm and add if missing. Edit `~/.config/hypr/bindings.conf` (or `hyprland.conf` if you don't have a split config):

```conf
# Hold Super + left mouse = drag window
bindm = SUPER, mouse:272, movewindow
# Hold Super + right mouse = resize window
bindm = SUPER, mouse:273, resizewindow
```

Reload: `hyprctl reload` or `Super + Esc`.

### 6.2 Show title bars so you can grab windows with the mouse

Hyprland hides title bars by default. Add them back so windows feel like windows:

```conf
# in ~/.config/hypr/hyprland.conf or a sourced file
general {
    border_size = 2
    gaps_in = 4
    gaps_out = 8
}

decoration {
    rounding = 8
    # keep shadow/blur as-is from your theme
}

# Enable title bars via a "group" plugin-free trick:
# use the "dwindle" layout and set default window settings
misc {
    enable_anr_dialog = true
    focus_on_activate = true
}
```

For actual draggable title bars, the cleanest option is the **hyprbars** plugin:

```bash
# Install hyprpm and the hyprbars plugin
hyprpm update
hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable hyprbars
```

Then in `~/.config/hypr/hyprland.conf`:

```conf
plugin {
    hyprbars {
        bar_height = 26
        bar_text_size = 12
        bar_text_font = JetBrainsMono Nerd Font
        col.text = rgba(e0def4ff)
        bar_color = rgba(1f1d2eee)

        # Mouse-friendly buttons (close / maximize / minimize)
        hyprbars-button = rgb(eb6f92), 14, , hyprctl dispatch killactive
        hyprbars-button = rgb(f6c177), 14, , hyprctl dispatch fullscreen 1
        hyprbars-button = rgb(9ccfd8), 14, , hyprctl dispatch movetoworkspacesilent special
    }
}
```

Now every tiled window has a bar you can click and drag with the mouse. Double-click to fullscreen, click buttons to close/max/min.

### 6.3 Add a persistent dock

Omarchy doesn't ship a dock. `nwg-dock-hyprland` is the best option — it's Hyprland-native and click-to-launch.

```bash
yay -S nwg-dock-hyprland
```

Autostart it. In `~/.config/hypr/autostart.conf` (or wherever your `exec-once` lines live):

```conf
exec-once = nwg-dock-hyprland -p bottom -i 48 -mt 8 -mb 8 -x -d -a end
```

Flags: `-p bottom` puts it on the bottom, `-i 48` icon size, `-d` enables autohide, `-a end` aligns to the end. Pinned apps are managed via its own config at `~/.config/nwg-dock-hyprland/`.

If you want a **macOS-style always-on dock**, drop `-d` and add `-f` (permanent).

**Alternative:** `nwg-drawer` gives you a GNOME/Plasma-style full-screen app grid (`nwg-drawer` as a command — bind it to a hot corner or a Waybar button).

### 6.4 Clickable, discoverable Waybar

Omarchy's Waybar already has some click handlers. Make more of it clickable and add a system tray so tray-apps (Slack, Discord, Steam, Dropbox) show up properly.

Edit `~/.config/waybar/config.jsonc`. Key changes:

```jsonc
{
    "layer": "top",
    "position": "top",
    "height": 32,

    "modules-left": ["custom/omarchy", "hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["tray", "pulseaudio", "network", "bluetooth", "cpu", "memory", "battery", "custom/power"],

    "hyprland/workspaces": {
        "on-click": "activate",
        "on-scroll-up": "hyprctl dispatch workspace e+1",
        "on-scroll-down": "hyprctl dispatch workspace e-1",
        "format": "{icon}",
        "format-icons": { "1":"1","2":"2","3":"3","4":"4","5":"5","active":"●","default":"○" }
    },

    "hyprland/window": { "max-length": 60 },

    "tray": { "icon-size": 18, "spacing": 8 },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "󰖁",
        "on-click": "pavucontrol",
        "on-click-right": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
        "on-scroll-up": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+",
        "on-scroll-down": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
        "format-icons": { "default": ["󰕿","󰖀","󰕾"] }
    },

    "network": {
        "format-wifi": "󰖩 {essid}",
        "format-ethernet": "󰈀 {ipaddr}",
        "on-click": "alacritty -e nmtui"
    },

    "bluetooth": {
        "format": "󰂯",
        "format-connected": "󰂱 {device_alias}",
        "on-click": "blueman-manager"
    },

    "clock": {
        "format": "{:%a %d %b  %H:%M}",
        "tooltip-format": "<tt><small>{calendar}</small></tt>",
        "on-click": "gnome-calendar"
    },

    "custom/power": {
        "format": "⏻",
        "on-click": "wlogout",
        "tooltip": false
    }
}
```

Install the supporting GUI tools for these clicks:
```bash
sudo pacman -S --needed pavucontrol blueman gnome-calendar wlogout network-manager-applet
```

Now: click the speaker → audio mixer. Click network → Wi-Fi chooser. Click clock → calendar. Click power icon → logout menu.

### 6.5 A mouse-friendly launcher (Walker grid mode, or Rofi)

Omarchy ships with Walker. It's fine with the keyboard — to make it mouse-friendly, switch its layout to **grid mode** with large icons.

`~/.config/walker/config.toml`:
```toml
[ui]
fullscreen = false

[ui.window.box]
width = 640
height = 480

[ui.window.box.scroll.list.item.icon]
icon_size = 48
```

Or if you prefer Rofi (works in both X11 and Wayland now):
```bash
sudo pacman -S rofi-wayland
```
And set up `~/.config/rofi/config.rasi` with `display-drun: drun;` and `icon-theme: "Papirus";`. Bind it in Hyprland:
```conf
bind = SUPER, D, exec, rofi -show drun -show-icons
```
This gives you a drawer you can mouse-click through.

### 6.6 Traditional file manager

CLI is nice but sometimes you just want to drag a file around. Install **Thunar** with its full plugin set:

```bash
sudo pacman -S --needed thunar thunar-volman thunar-archive-plugin file-roller gvfs gvfs-mtp tumbler ffmpegthumbnailer
```

Autostart the volume manager (so USB sticks auto-mount):
```conf
# in ~/.config/hypr/autostart.conf
exec-once = thunar --daemon
```

Add a keyboard shortcut and pin it to the dock:
```conf
bind = SUPER, E, exec, thunar
```

**Alternative:** `nautilus` (GNOME Files) is slicker but pulls in more GNOME dependencies. `nemo` (Cinnamon's fork) is also excellent.

### 6.7 Alt-Tab window switching

By default Hyprland doesn't do Alt-Tab. Add it:

```conf
# Cycle through windows on current workspace
bind = ALT, Tab, cyclenext
bind = ALT, Tab, bringactivetotop

# Cycle backward
bind = ALT SHIFT, Tab, cyclenext, prev
bind = ALT SHIFT, Tab, bringactivetotop
```

For a visual Alt-Tab switcher with a popup window list:
```bash
yay -S hyprswitch
```
Then bind `hyprswitch gui` to Alt-Tab. It shows a grid of window previews you can click.

### 6.8 Floating-by-default for the apps you want

Tiling is great until you want a calculator to stay small. Add per-app floating rules:

```conf
# ~/.config/hypr/windowrules.conf
windowrulev2 = float, class:^(pavucontrol)$
windowrulev2 = float, class:^(blueman-manager)$
windowrulev2 = float, class:^(org.gnome.Calculator)$
windowrulev2 = float, class:^(nm-connection-editor)$
windowrulev2 = float, title:^(Open File)(.*)$
windowrulev2 = float, title:^(Save File)(.*)$
windowrulev2 = float, class:^(file_progress)$
windowrulev2 = float, class:^(thunar)$, title:^(File Operation Progress)$
```

### 6.9 Desktop right-click and idle behavior

Wayland/Hyprland has no "desktop" — the wallpaper is non-interactive. Workarounds:

- Use a **hot corner** via `hyprland-plugins` → `hyprspace` for window overview.
- Bind **right-click anywhere** to a context menu via `wofi`:

```conf
bind = , mouse:273, exec, [ -z "$(hyprctl activewindow -j | jq -r .class)" ] && wofi --show dmenu
```

Realistically, most people just use the Waybar and dock for mouse workflow and leave the wallpaper alone.

### 6.10 Make Hyprland's scratchpad actually useful with the mouse

Scratchpad = a hidden workspace you can toggle. Great for a persistent terminal or a notes app:

```conf
# Bring up a floating terminal scratchpad with Super+`
bind = SUPER, grave, togglespecialworkspace, term
bind = SUPER SHIFT, grave, movetoworkspace, special:term
windowrulev2 = float, workspace:special:term
windowrulev2 = size 1000 600, workspace:special:term
```

### 6.11 Reload and test

```bash
hyprctl reload
```
Or just hit `Super + Esc` (Omarchy default).

---

## 7. Recommended Additional Software

### Browser
Pick via Omarchy menu → Install → Browser. Defaults are:
- Chromium (ships with Omarchy)
- Firefox (`sudo pacman -S firefox`)
- Brave (`yay -S brave-bin`)
- Zen Browser (`yay -S zen-browser-bin`) — nice Firefox fork

### Editor / IDE
Omarchy ships Neovim. From the Omarchy menu, Install → Editor adds:
- VS Code (`code`)
- Cursor
- Zed
- Sublime Text

### Terminal
Omarchy uses **Ghostty** by default. It's great. Alternatives: `alacritty`, `kitty`, `wezterm`.

### Media & productivity
```bash
# Media
sudo pacman -S --needed vlc mpv imv
yay -S spotify

# Office
sudo pacman -S --needed libreoffice-fresh hunspell-en_au

# Communication (pick what you need)
sudo pacman -S --needed thunderbird signal-desktop
yay -S slack-desktop discord zoom

# Graphics / creative
sudo pacman -S --needed gimp inkscape krita obs-studio blender

# Dev tooling (Omarchy includes most of this already)
sudo pacman -S --needed docker docker-compose lazygit ripgrep fd fzf bat eza zoxide
sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # re-login after this
```

### Gaming
```bash
sudo pacman -S --needed steam lutris gamemode lib32-gamemode mangohud lib32-mangohud
yay -S heroic-games-launcher-bin protonup-qt
```

### Fonts you'll want
Omarchy installs JetBrainsMono Nerd Font. Add a few more so everything renders well:
```bash
sudo pacman -S --needed noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-liberation ttf-dejavu
yay -S ttf-ms-fonts    # Microsoft fonts (Arial, Times, etc.) for web compat
```

---

## 8. Maintenance & Updates

### Daily driver commands
```bash
# Update everything (Arch + AUR + Omarchy)
omarchy-update
# or plain:
sudo pacman -Syu && yay -Syu

# Clean package cache
sudo pacman -Sc

# Check what's installed & big
pacman -Qi | awk '/^Name/{n=$3}/^Installed Size/{print $4$5, n}' | sort -h
```

### Snapshots (so a bad update can't brick you)
You're on btrfs — use **Snapper** or **Timeshift** to snapshot before upgrades.

```bash
sudo pacman -S --needed snapper snap-pac grub-btrfs
sudo snapper -c root create-config /
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

`snap-pac` auto-creates a snapshot every time you `pacman -Syu`. `grub-btrfs` adds a boot menu entry to boot into a past snapshot if an update goes sideways. (If you picked systemd-boot at install, use `limine-snapper-sync` instead, or switch to GRUB for this feature.)

### Firewall
Omarchy enables `ufw` by default. Confirm:
```bash
sudo ufw status verbose
```

### When something breaks
Read the Arch news before updating: `informant` is a tool that blocks `pacman -Syu` until you've acknowledged recent Arch news.
```bash
yay -S informant
```

---

## 9. Troubleshooting

**Black screen after boot (NVIDIA)**  
Verify `nvidia_drm.modeset=1` is in kernel params. Confirm modules in `mkinitcpio.conf`. Regenerate initramfs: `sudo mkinitcpio -P`.

**Hyprland won't start / crashes immediately**  
Check `~/.local/share/hyprland/hyprland.log`. Most common cause: a bad config line after editing. Revert your last change.

**Fractional scaling looks blurry on Electron apps**  
Electron/Chromium on Wayland sometimes needs flags. Create `~/.config/electron-flags.conf`:
```
--enable-features=UseOzonePlatform,WaylandWindowDecorations
--ozone-platform=wayland
```

**Bluetooth doesn't appear**  
```bash
sudo systemctl enable --now bluetooth
```

**Sleep/suspend wakes up immediately**  
Usually a USB device. Check `cat /proc/acpi/wakeup` and disable culprits. On desktops this is often the keyboard/mouse — fine to leave enabled.

**Audio going to the wrong sink**  
Open `pavucontrol` (click the speaker in Waybar if you followed 6.4) → Output Devices → set default.

**Want to unbind the disk encryption prompt at login**  
You can't safely — but you can use `systemd-cryptenroll` to unlock with a TPM2 chip (if your board has one) so boot is automatic while data stays encrypted:
```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
```

**Omarchy update breaks something**  
```bash
omarchy-update --revert
```
Or pick a snapshot from the boot menu.

---

## Appendix A: Fully Manual Path (No Omarchy)

If you prefer to build the Omarchy-style stack yourself, here's the minimal package set and wiring. Run after section 4 instead of section 5.

### A.1 Core stack
```bash
sudo pacman -S --needed \
    hyprland waybar wofi rofi-wayland dunst \
    hyprpaper hyprlock hypridle hyprshot hyprpicker \
    xdg-desktop-portal-hyprland qt5-wayland qt6-wayland \
    polkit-gnome thunar thunar-volman file-roller gvfs \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    pavucontrol brightnessctl playerctl \
    grim slurp wl-clipboard cliphist \
    ghostty neovim git \
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
```

### A.2 Login manager
Pick one:
- **Autologin to TTY + UWSM** (Omarchy's approach — fastest)
- **greetd + tuigreet** (clean, minimal)
- **SDDM** (Plasma-style graphical login, mouse-friendly)

SDDM install:
```bash
sudo pacman -S sddm
sudo systemctl enable sddm
```

Create `~/.config/hypr/hyprland.conf` — use [hypr.land/configuring](https://wiki.hypr.land/Configuring/) as reference. Copy a community config like [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) or [prasanthrangan/hyprdots](https://github.com/prasanthrangan/hyprdots) to skip hours of boilerplate.

### A.3 Autostart essentials
```conf
# ~/.config/hypr/hyprland.conf
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = waybar
exec-once = dunst
exec-once = hyprpaper
exec-once = hypridle
exec-once = wl-paste --watch cliphist store
exec-once = nm-applet --indicator
exec-once = thunar --daemon
```

Apply all the section 6 tweaks and you'll have an Omarchy-ish setup without the Omarchy layer.

---

## Appendix B: Cheat Sheet — Default Omarchy Keybindings

| Binding | Action |
|---|---|
| `Super + Alt + Space` | Omarchy menu (everything else is discoverable from here) |
| `Super + Enter` | Terminal |
| `Super + B` | Browser |
| `Super + F` | File manager |
| `Super + Space` | App launcher (Walker) |
| `Super + W` | Close window |
| `Super + V` | Toggle floating |
| `Super + J` | Toggle split direction |
| `Super + 1..9` | Switch to workspace N |
| `Super + Shift + 1..9` | Move window to workspace N |
| `Super + Arrow keys` | Move focus |
| `Super + Shift + Arrow` | Move window in layout |
| `Super + LMB drag` | Move window (floating) |
| `Super + RMB drag` | Resize window |
| `Super + Esc` | Reload Hyprland |
| `Print` | Screenshot region |
| `Super + Print` | Screenshot window |

---

## Appendix C: Where to go next

- **Omarchy Manual:** https://learn.omacom.io/2/the-omarchy-manual
- **Hyprland Wiki:** https://wiki.hypr.land
- **Arch Wiki:** https://wiki.archlinux.org (the single best Linux resource anywhere)
- **r/unixporn** and **r/hyprland** for inspiration
- **`awesome-omarchy`** list: https://github.com/aorumbayev/awesome-omarchy — tons of plugins, themes, and tools

---
