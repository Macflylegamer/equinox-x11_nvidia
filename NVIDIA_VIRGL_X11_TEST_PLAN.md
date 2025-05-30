# Equinox: Test and Validation Plan for Nvidia GPU and X11 Support

**Goal:** Outline the testing strategy, specific test cases, validation methods, and expected outcomes for the implemented Nvidia/VirGL/X11 features. This plan will serve as a guide for manual testing.

**I. Host System Setup for Testing:**

1.  **OS:** A Linux distribution with X11 (Xorg) as the display server.
2.  **Nvidia GPU:** An Nvidia GPU compatible with VirGL (most modern GPUs should be).
3.  **Nvidia Drivers:** Latest proprietary Nvidia drivers installed correctly, providing OpenGL and GLX support. Verify with `nvidia-smi` and `glxinfo | grep "OpenGL renderer string"`.
4.  **Dependencies:** All host dependencies listed in `BUILDING.md` (under the "Experimental Nvidia GPU / VirGL / X11 Support Dependencies" section) must be installed (e.g., `virglrenderer-devel`, `libX11-devel`, `libepoxy-devel`, etc.).
5.  **Equinox Build:** Equinox must be freshly built from the source code branch containing these Nvidia/VirGL/X11 features.
6.  **Xauthority:** Ensure X11 authentication is correctly configured. The Equinox wrapper script or the user might need to ensure the host's Xauthority file (e.g., `$HOME/.Xauthority` or a path like `/run/user/1000/gdm/Xauthority`) is correctly bind-mounted or copied to the path specified in the LXC configuration for the container (e.g., `/run/equinox/xauthority`). The `DISPLAY` environment variable must also be correctly set and available to the Equinox process.

**II. Container (Android Image) Setup:**

1.  Ensure the Android image used by Equinox contains a Mesa build with the VirGL guest DRI driver (`virpipe_dri.so` or similar). This allows Android to render to a VirGL context.
2.  Verify Android properties are set as expected (e.g., `ro.hardware.egl=mesa`, `ro.hardware.gralloc` is appropriate, and `gralloc.gbm.device` points to a valid DRI node if GBM is used by gralloc). These can be checked via Equinox logs (which show some HAL properties) or by using `getprop` within the container if accessible.

**III. Test Cases & Validation Methods:**

*   **TC1: Successful Launch and Basic Operation (Happy Path)**
    *   **Action:** Launch Equinox, then launch Roblox from the Equinox interface.
    *   **Validation:**
        *   Roblox application starts and is playable.
        *   Monitor `nvidia-smi` on the host: Look for a process associated with Equinox (or a child process spawned for VirGL/Roblox) consuming GPU resources (memory, utilization).
        *   Check Equinox logs for any errors. Specifically, look for successful VirGL initialization messages and debug logs from the `host_*` callback functions.
        *   If possible, check Android `logcat` (e.g., via `lxc-attach` or if Equinox provides a way to view it) for graphics-related errors (EGL, OpenGL ES, SurfaceFlinger).
    *   **Expected Outcome:** Smooth graphics rendering within Roblox. No major visual artifacts (tearing, flickering, missing textures). GPU utilization should be observable on `nvidia-smi`, indicating hardware acceleration. Equinox logs should show successful VirGL initialization and subsequent callback invocations without errors.

*   **TC2: X11 `DISPLAY` Misconfiguration**
    *   **Action:** Before launching Equinox, intentionally set an incorrect `DISPLAY` environment variable in the terminal where Equinox will be launched (e.g., `export DISPLAY=:99`).
    *   **Validation:** Observe Equinox launch behavior. Check Equinox logs.
    *   **Expected Outcome:** Equinox should fail to initialize its X11 components for VirGL. The logs should clearly indicate this, ideally with the message: "VirGL: Failed to open X11 display. Ensure X server is running and DISPLAY environment variable is correctly set" (from the `XOpenDisplay` failure in `initVirgl`). The application might terminate or fail to render graphics.

*   **TC3: Xauthority Misconfiguration**
    *   **Action:** Ensure the Xauthority file is *not* correctly set up at the path expected by the LXC configuration (e.g., by not creating the symlink or bind-mount to `/run/equinox/xauthority`).
    *   **Validation:** Observe Equinox launch and Roblox startup. Check Equinox logs and potentially system X11 logs.
    *   **Expected Outcome:** Equinox might fail to connect to the X server or render graphics. `XOpenDisplay` might succeed, but subsequent X11 operations or GLX context creation/make_current could fail. Logs from Xlib (if captured by Equinox logging) might indicate an authorization failure. This can be hard to distinguish from other X11 errors solely from application logs, but it's a key test for X11 security integration.

*   **TC4: Missing Nvidia Host Devices (Conceptual/Simulated)**
    *   **Action:** This test is primarily based on code review and log analysis, as altering `/dev` nodes on a live system is risky. The focus is on how Equinox handles missing devices that are part of its LXC configuration.
    *   **Validation:** Review LXC configuration in `src/container/configs/config_base.lx` to ensure Nvidia device mounts (`/dev/nvidia0`, `/dev/nvidiactl`, etc.) are marked `optional`. If not, LXC container startup would fail if devices are missing. Check Equinox logs for errors from `host_get_drm_fd` if it's called and cannot find/open the expected DRI render node (which is now supported for Nvidia).
    *   **Expected Outcome:** If LXC mounts are optional, the container should still start. If `host_get_drm_fd` is called, it should log an error like "VirGL: host_get_drm_fd - DRM node not found for VirGL" or "Failed to open DRM node...". Graphics might fail or fall back to software rendering if VirGL critically depends on this FD.

*   **TC5: VirGL Initialization Failure (e.g., Incompatible virglrenderer on host)**
    *   **Action:** This is difficult to simulate without having multiple, potentially incompatible, versions of `virglrenderer`. The test relies on the existing error handling for `virgl_renderer_init`.
    *   **Validation:** Check Equinox logs.
    *   **Expected Outcome:** If `virgl_renderer_init` fails, Equinox logs should show the critical error message: "VirGL: CRITICAL - Failed to initialize VirGL renderer. Error code: [...] Check VirGL/Mesa versions and GPU compatibility. Equinox may not function correctly or will have significantly reduced performance."

*   **TC6: Graphics Performance and Visual Artifacts**
    *   **Action:** Launch and play a variety of Roblox games/experiences, including those known to be graphically demanding.
    *   **Validation:**
        *   Subjectively assess graphics quality: Look for any visual artifacts such as tearing, flickering, incorrect colors, missing or corrupted textures, Z-fighting.
        *   Subjectively assess performance: Frame rate should be reasonably smooth and playable, consistent with the capabilities of the host Nvidia GPU. Compare against expected performance if possible (e.g., native Windows Roblox on similar hardware, or other Linux workarounds).
    *   **Expected Outcome:** Good to excellent visual quality with no significant artifacts. Acceptable and stable performance, indicating that hardware acceleration via VirGL and Nvidia is effective.

*   **TC7: Window Management and Interaction**
    *   **Action:** While Roblox is running, test window management features:
        *   Resizing the Roblox window (if the game/Equinox setup allows windowed mode that is resizable).
        *   Minimizing and restoring the window.
        *   Switching to full-screen mode and back (if supported).
        *   Alt-tabbing away from and back to the Roblox window.
    *   **Validation:** Ensure the application responds correctly to these actions. Rendering should adapt to new window sizes without glitches or crashes. The application should remain stable.
    *   **Expected Outcome:** Roblox remains stable and renders correctly during and after all tested window operations.

**IV. Logging and Debugging Tools:**

*   **Equinox Application Logs:** The primary source for VirGL, X11, and GLX related messages. Set log level to `debug` if possible during testing for maximum verbosity.
*   **`nvidia-smi` (Host):** Useful for monitoring GPU utilization, memory usage, and identifying processes using the Nvidia GPU.
*   **`glxinfo` (Host):** To verify host GLX capabilities, server/client versions, and available visuals.
*   **LXC Logs:** Can be generated using `lxc-start -n <container_name> --logfile /path/to/lxc.log --logpriority DEBUG`. Useful for diagnosing issues during container startup, especially related to device passthrough and mount points defined in LXC configuration.
*   **Android `logcat` (Guest):** If accessible (e.g., via `lxc-attach -n <container_name> -- logcat`), this can provide valuable insights into graphics-related issues from the Android guest's perspective (SurfaceFlinger, EGL, GLES drivers).
*   **X11 Logs (Host):** Typically located at `/var/log/Xorg.0.log`. May contain low-level X server errors or Nvidia X driver messages, though less likely to be directly caused by Equinox application logic unless it's triggering a driver bug or severe misconfiguration.

This test plan provides a structured approach to validating the Nvidia GPU and X11 support features. Each test case is designed to verify specific aspects of the implementation, from basic functionality to error handling and performance.
