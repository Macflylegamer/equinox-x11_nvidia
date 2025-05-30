# <img width="36" src="assets/equinox.svg"> equinox
Equinox is a runtime for Roblox on Linux that uses LXC containers to run (y)our beloved lego game.

| | | | |
|-------------------|--------------------|------------------|-------------|
|<img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox001.jpg"> | <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox002.jpg"> | <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox003.jpg">
| <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox004.jpg"> | <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox005.jpg"> | <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox007.png"> | <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox006.jpg"> | <img src="https://raw.githubusercontent.com/equinoxhq/equinox/refs/heads/master/images/equinox008.jpg">


# Progress
- [X] Get a container running
- [X] Get the GPU working in the container
- [X] Make it run Roblox
- [X] Discord RPC
- [X] BloxstrapRPC
- [ ] PC-exclusive game support
- [X] Proper mouselocking support* <small>(with caveats)</small>
- [ ] All configuration options from Lucem 2.x
- [ ] New configuration options (possibly like Sober's asset overlay?)

# Known Issues (These will be fixed sooner or later)
- Performance is really bad in certain games (Arsenal, Dead Rails, etc.)
- Graphical artifacting on integrated GPUs
- Mouse locking sometimes does not work
- PC-exclusive games are not playable (Project Remix, Arcane Odyssey, etc.)

# Known Issues (Which are a long-term goal to fix)
- **Nvidia GPU Support (Experimental):** Support for Nvidia GPUs via VirGL on X11 has been implemented. This is an experimental feature.
  - **Setup & Dependencies:** Requires specific host libraries and configurations. See the "Experimental Nvidia GPU / VirGL / X11 Support Dependencies" section in `BUILDING.md` for details.
  - **Limitations and Known Issues (Nvidia/VirGL/X11):**
    - Performance may vary depending on the Nvidia GPU model, driver version, and specific Roblox game.
    - The current VirGL fence implementation is synchronous (`glClientWaitSync` with `GL_TIMEOUT_IGNORED`), which might impact performance in some scenarios. Asynchronous fencing could be explored for further optimization.
    - This solution is specific to X11 (Xorg). Wayland-native Nvidia support is not yet implemented.
    - Compatibility with all Nvidia driver versions or GPU generations is not guaranteed.
    - Debugging graphics issues can be complex, requiring knowledge of X11, GLX, VirGL, and Nvidia driver interactions.
    - Some Roblox games might still exhibit graphical glitches or performance issues that are unrelated to the host GPU acceleration (i.e., existing general issues).
- Wayland-native GPU acceleration for Nvidia (beyond Xwayland) is a future consideration.
