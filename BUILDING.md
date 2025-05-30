# Building Equinox
This aims to be a comprehensive guide to compiling Equinox from scratch. If your distribution has a package for Equinox, you needn't do this.

# Installation
## Dependencies Required (For people interested in packaging Equinox)
### Library Dependencies
1. glib
2. [libgbinder](https://github.com/mer-hybris/libgbinder)
3. pcre2
4. gtk4
5. libadwaita

### Compile-Time Dependencies
1. clang
2. make

### Runtime Dependencies
1. lxc
2. dnsmasq

## Arch
Run the following command to gather all dependencies needed by Equinox on Arch Linux.
```
# pacman -S clang make gtk4 libadwaita glib2 glib2-devel pcre2 lxc dnsmasq
```
Now, you need to install libgbinder, which you can do by using your favourite AUR helper (we're using `yay` in this example, but you can use any AUR helper you fancy.)

```
# yay -S libgbinder
```

Some users have reported that the following command fails. If it does, run this command instead:

```
# yay -S libgbinder-git
```

## Fedora
Run the following command to gather all dependencies needed by Equinox on Fedora.
```
# dnf install build-essential clang gtk4 gtk4-devel libadwaita libadwaita-devel pcre2 pcre2-devel glib2 glib2-devel lxc dnsmasq
```

Now, unfortunately, Fedora does not have a libgbinder package in its repositories. You'll need to manually clone the repository and compile it instead. 
The following one-liner will do it for you:
```
$ git clone https://github.com/mer-hybris/libgbinder.git /tmp/equinox-gbinder && cd /tmp/equinox-gbinder && make -j$(nproc) && sudo make install
```

**NOTICE**: Fedora uses [SELinux](https://en.wikipedia.org/wiki/Security-Enhanced_Linux) by default. Equinox cannot work with it yet. Hence, you'll need to disable SELinux.

### Disabling SELinux
SELinux can bork Equinox entirely. Here's how to make sure it doesn't.
You'll need to run this every reboot.
```
# setenforce Permissive
```

## Ubuntu
Run the following command to gather all dependencies needed by Equinox on Ubuntu.
```
# apt-get update && apt-get install clang make gtk4 libgtk-4-dev libadwaita-1 libadwaita-1-dev pcre2 libpcre2-dev glib2.0 libglib2.0-dev lxc lxc-templates uidmap lxc-utils bridge-utils dnsmasq
```

Now, unfortunately, just like Fedora, Ubuntu does not have a libgbinder package in its repositories. You'll need to manually clone the repository and compile it instead.
The following one-liner will do it for you:
```
$ git clone https://github.com/mer-hybris/libgbinder.git /tmp/equinox-gbinder && cd /tmp/equinox-gbinder && make -j$(nproc) && sudo make install
```

# Obtaining Nim
Equinox require a Nim version beyond 2.2.2
Run the following one-liner to get Nim and properly install it for your user:
```sh
$ curl https://nim-lang.org/choosenim/init.sh -sSf | sh && echo "PATH=$HOME/.nimble/bin:$PATH" >> ~/.bashrc
```
Note that the second half of this command will add the path to `.bashrc` only.

## Or add nimble to your PATH manually
You can add `:$HOME/.nimble/bin` to your `PATH` export in `.bashrc` or other shell config like the following:
```sh
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.nimble/bin:$PATH"
```

**Make sure you didn't mess up the config.** Then just reload your `.bashrc` or other shell config.

# Compiling Equinox
After following the above instructions, run:
```
$ nimble install https://github.com/equinoxhq/equinox
```
This will compile Equinox and install it for your user.

# Running Equinox
To run Equinox, run this in your terminal:
```
$ equinox_gui auto
```
This is for the first run. After this, Equinox will create a desktop entry for you that'll let you launch it from your application launcher without the terminal.

---

## Experimental Nvidia GPU / VirGL / X11 Support Dependencies
The following are additional dependencies required for experimental support of Nvidia GPUs via VirGL and X11. This is an advanced feature currently under development.

### Host System Requirements:
*   **Proprietary Nvidia Drivers:** Ensure the official Nvidia proprietary drivers are installed and working correctly on your host system.
*   **X11 Server:** An X11 server (Xorg) must be running. Wayland-only environments will not work with this experimental X11-based rendering.
*   **Development Packages:** You will need the development packages for the following libraries. Package names may vary by distribution (e.g., `-dev` for Debian/Ubuntu, `-devel` for Fedora/SUSE).
    *   **virglrenderer:** Provides the VirGL renderer library (e.g., `libvirglrenderer-devel`, `virglrenderer-devel`).
    *   **X11 Libraries:** Core X11 and X extension libraries (e.g., `libX11-devel`, `libXext-devel`).
    *   **OpenGL/GLX Libraries:** For host-side OpenGL context creation. Nvidia drivers typically provide `libGL.so`, `libGLX.so`, etc., but development headers might be needed separately (e.g., `libglvnd-devel`, `mesa-libGL-devel`, `libGLX-devel`, or Nvidia-specific SDKs if applicable).
    *   **libepoxy (Recommended):** A library for handling OpenGL function pointers, which can simplify GLX/EGL management (e.g., `libepoxy-devel`).
    *   *(Package names for specific distributions can be added here as they are confirmed.)*

### Guest (Android Container) Requirements:
*   **Mesa with VirGL Driver:** The Android image used within the LXC container must have Mesa compiled with support for the VirGL guest driver (`virpipe_dri.so`). This allows the Android system to send rendering commands to VirGL.

**Note on `pkg-config` and `virglrenderer`**: If you have `libvirglrenderer-devel` (or your system's equivalent) installed but the build process still reports errors related to `virglrenderer` not being found during C compilation (e.g., `Package 'virglrenderer', required by 'virtual:world', not found` or missing headers/symbols), ensure that your `PKG_CONFIG_PATH` environment variable includes the directory where `virglrenderer.pc` is installed. Common paths for `.pc` files include `/usr/lib/pkgconfig`, `/usr/lib64/pkgconfig`, `/usr/share/pkgconfig`, and `/usr/local/lib/pkgconfig`. You may need to set this variable in your shell before building, for example:
```sh
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
```
(Adjust the path according to your system.)

**Note:** This feature is experimental. Functionality, performance, and stability are not guaranteed. The necessary LXC configurations and VirGL initialization are being actively developed.

