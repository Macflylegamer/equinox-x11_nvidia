import std/[os, logging, options, strutils, sequtils, tables]
import pkg/[glob]

const UnsupportedGPUDrivers* = [
  # "nvidia" # TODO: novideo support........
]

type
  InvalidRenderDevice* = object of ValueError
  NoVulkanSupport* = object of ValueError

  DRINode* = object
    dev*: string
    gpu*: string

proc getKernelDriver*(device: string): string =
  readFile("/sys/class/drm/" & device & "/device/uevent").split("DRIVER=")[1].split(
    '\n'
  )[0]

proc getCardFromRenderNode*(device: string): string =
  debug "container/gpu: getCardFromRenderNode(" & device & ')'
  var matches: seq[string]

  for kind, node in walkDir("/sys/class/drm" / device / "device/drm"):
    if kind != pcDir:
      continue

    if node.contains("card"):
      matches &= node

  if matches.len < 1:
    error "container/gpu: invalid/unregistered rendering node: " & device
    raise newException(
      InvalidRenderDevice,
      "found 0 matches for the card that owns this node! (" & device & ')',
    )

  if matches.len > 1:
    warn "container/gpu: multiple DRM devices seem to own a single render node: " &
      device
    warn "container/gpu: this is weird; will it lead to a crash? :P"

  "/dev" / "dri" / matches[0].splitPath().tail

proc getDriNode*(): Option[DRINode] =
  let nodes = glob("/dev/dri/renderD*").walkGlob.toSeq()

  for node in nodes:
    let split = splitPath(node).tail
    let renderDev = split

    if getKernelDriver(renderDev) notin UnsupportedGPUDrivers:
      debug "container/gpu: found supported DRI node: " & renderDev
      return some(DRINode(dev: node, gpu: getCardFromRenderNode(renderDev)))
    else:
      warn "container/gpu: found unsupported DRI node: " & renderDev
      warn "container/gpu: ignoring it."

proc getVulkanDriver*(device: string): string =
  if existsEnv("EQUINOX_VK_DRIVER"):
    warn "container/gpu: using overwritten EQUINOX_VK_DRIVER: " &
      getEnv("EQUINOX_VK_DRIVER").repr
    return getEnv("EQUINOX_VK_DRIVER")

  let table = {
    "i915": "intel",
    "amdgpu": "radeon",
    "radeon": "radeon",
    "panfrost": "panfrost",
    "msm": "freedreno",
    "msm_dpu": "freedreno",
    "vc4": "broadcom",
    "nouveau": "nouveau",
  }.toTable
  let kernelDriver = getKernelDriver(device)

  if kernelDriver notin table:
    error "container/gpu: Your GPU does not support Vulkan."
    error "container/gpu: If you believe that this is a mistake, open a support ticket in the Lucem Discord server."
    raise newException(
      NoVulkanSupport, "Device \"" & device & "\" does not support Vulkan!"
    )

  table[kernelDriver]

# VirGL Renderer Integration
# Assuming virglrenderer bindings are available via a package import
# This might need adjustment based on the actual project structure for virglrenderer.
import pkg/virglrenderer # Adjust if import path is different

# X11 and GLX Host-side OpenGL integration for VirGL callbacks
# These pragmas instruct Nim to link against X11 and OpenGL (GLX).
# Ensure these libraries and their development headers (e.g., libX11-devel, libGL-devel) are installed.
{.push importc, header: "<X11/Xlib.h>", dynlib: "libX11.so.6".}
{.push importc, header: "<GL/glx.h>", dynlib: "libGL.so.1".}
# Also import GL headers for sync objects, assuming these are part of libGL.so.1 or accessible.
# If these are in a different library or need specific extension loading (like via Epoxy),
# this might need adjustment. For common desktop OpenGL, they are often in libGL.
{.push importc, header: "<GL/gl.h>".} # No separate dynlib needed if part of libGL.so.1
# For libepoxy, if used:
# {.push importc, header: "<epoxy/glx.h>", dynlib: "libepoxy.so.0".}
# {.push importc, header: "<epoxy/gl.h>", dynlib: "libepoxy.so.0".}
import posix # For open, close, O_RDWR

# GL Sync Object Types and Constants
type
  GLsync {.importc: "GLsync", header: "<GL/gl.h>".} = pointer

const
  GL_SYNC_GPU_COMMANDS_COMPLETE* = 0x9117
  GL_SYNC_FLUSH_COMMANDS_BIT* = 0x00000001
  GL_TIMEOUT_IGNORED* = 0xFFFFFFFFFFFFFFFF # Cast to uint64 when used

# GL Sync Functions
proc glFenceSync*(condition: cuint, flags: cuint): GLsync {.importc: "glFenceSync", dynlib: "libGL.so.1".}
proc glClientWaitSync*(sync: GLsync, flags: cuint, timeout: uint64): cuint {.importc: "glClientWaitSync", dynlib: "libGL.so.1".}
proc glDeleteSync*(sync: GLsync): void {.importc: "glDeleteSync", dynlib: "libGL.so.1".}
# Might need glGetInteger64v for more detailed sync checks later.

# X11 Types (subset, more can be added from Xlib.h and Xutil.h as needed)
type
  DisplayX {.importc: "Display", header: "<X11/Xlib.h>".} = object # opaque struct, treat as ptr
  WindowX {.importc: "Window", header: "<X11/Xlib.h>".} = culong
  VisualID {.importc: "VisualID", header: "<X11/Xlib.h>".} = culong
  XVisualInfo {.importc: "XVisualInfo", header: "<X11/Xlib.h>".} = object
    visual*: ptr VisualX # Visual pointer
    visualid*: VisualID
    screen*: cint
    depth*: cint
    classx*: cint # Renamed from 'class' to avoid Nim keyword conflict
    red_mask*: culong
    green_mask*: culong
    blue_mask*: culong
    colormap_size*: cint
    bits_per_rgb*: cint
  VisualX {.importc: "Visual", header: "<X11/Xlib.h>".} = object # opaque struct

# GLX Types (subset)
type
  GLXContext {.importc: "GLXContext", header: "<GL/glx.h>".} = pointer # Opaque pointer
  GLXDrawable {.importc: "GLXDrawable", header: "<GL/glx.h>".} = culong # Usually XID (Window, Pixmap, GLXPbuffer)
  GLXPbuffer {.importc: "GLXPbuffer", header: "<GL/glx.h>".} = culong

# GLX Constants (subset)
const
  GLX_USE_GL* = 1
  GLX_BUFFER_SIZE* = 2
  GLX_LEVEL* = 3
  GLX_RGBA* = 4
  GLX_DOUBLEBUFFER* = 5
  GLX_STEREO* = 6
  GLX_AUX_BUFFERS* = 7
  GLX_RED_SIZE* = 8
  GLX_GREEN_SIZE* = 9
  GLX_BLUE_SIZE* = 10
  GLX_ALPHA_SIZE* = 11
  GLX_DEPTH_SIZE* = 12
  GLX_STENCIL_SIZE* = 13
  GLX_ACCUM_RED_SIZE* = 14
  GLX_ACCUM_GREEN_SIZE* = 15
  GLX_ACCUM_BLUE_SIZE* = 16
  GLX_ACCUM_ALPHA_SIZE* = 17
  GLX_DRAWABLE_TYPE* = 0x8010
  GLX_PBUFFER_BIT* = 0x00000004
  GLX_RENDER_TYPE* = 0x8011
  GLX_RGBA_BIT* = 0x00000001
  GL_TRUE* = 1 # From OpenGL, but often used with GLX

# X11 Functions (imported via push/dynlib)
proc XOpenDisplay*(display_name: cstring): ptr DisplayX {.importc: "XOpenDisplay", dynlib: "libX11.so.6".}
proc XCloseDisplay*(display: ptr DisplayX): cint {.importc: "XCloseDisplay", dynlib: "libX11.so.6".}
proc XDefaultScreen*(display: ptr DisplayX): cint {.importc: "XDefaultScreen", dynlib: "libX11.so.6".}
proc XRootWindow*(display: ptr DisplayX, screen_number: cint): WindowX {.importc: "XRootWindow", dynlib: "libX11.so.6".}
proc XCreateSimpleWindow*(display: ptr DisplayX, parent: WindowX, x: cint, y: cint, width: cuint, height: cuint, border_width: cuint, border: culong, background: culong): WindowX {.importc: "XCreateSimpleWindow", dynlib: "libX11.so.6".}
proc XFree*(data: pointer): cint {.importc: "XFree", dynlib: "libX11.so.6".}
proc XDestroyWindow*(display: ptr DisplayX, w: WindowX): cint {.importc: "XDestroyWindow", dynlib: "libX11.so.6".}

# GLX Functions (imported via push/dynlib)
proc glXChooseVisual*(dpy: ptr DisplayX, screen: cint, attribList: ptr cint): ptr XVisualInfo {.importc: "glXChooseVisual", dynlib: "libGL.so.1".}
proc glXCreateContext*(dpy: ptr DisplayX, vis: ptr XVisualInfo, shareList: GLXContext, direct: cint): GLXContext {.importc: "glXCreateContext", dynlib: "libGL.so.1".}
proc glXDestroyContext*(dpy: ptr DisplayX, ctx: GLXContext): void {.importc: "glXDestroyContext", dynlib: "libGL.so.1".}
proc glXMakeCurrent*(dpy: ptr DisplayX, drawable: GLXDrawable, ctx: GLXContext): cint {.importc: "glXMakeCurrent", dynlib: "libGL.so.1".}
{.pop.} # End importc block

# Module-level X11/GLX state
var
  hostDisplay {.threadvar.}: ptr DisplayX = nil
  # A simple window for GLX contexts if needed as a default drawable.
  # VirGL might manage its own scanout surfaces, this is a fallback/default.
  defaultHostWindow {.threadvar.}: WindowX = 0 # 0 is None/Null for Window XID
  # TODO: Proper management of this window (creation/destruction)
  drmRenderNodeFd {.threadvar.}: cint = -1 # Cached DRM render node FD for get_drm_fd

# VirGL Host Callbacks Implementation

proc host_write_fence(cookie: pointer, fence_id: uint32): void {.cdecl.} =
  debug "VirGL: host_write_fence called, fence_id: ", fence_id
  # Ensure a context is current. This is a simplified check.
  # A robust solution might involve using the cookie or other means to ensure the correct context.
  if hostDisplay == nil:
    error "VirGL: host_write_fence - X11 display not initialized."
    return
  # TODO: This check for current context is problematic as host_make_current(nil,0,nil) unbinds.
  # We need a reliable way to ensure a context is current or this callback might operate incorrectly.
  # For now, proceed with caution, assuming virglrenderer ensures a context is current if needed for fences.

  # if glXGetCurrentContext() == nil: # A more direct check if available and reliable
  #   warn "VirGL: host_write_fence - No GLX context currently bound. Fence may not operate as expected."
  #   # Depending on driver/VirGL behavior, might return or proceed.

  let syncObj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0) # 0 for flags
  if syncObj == nil:
    error "VirGL: host_write_fence - glFenceSync failed. This can lead to rendering synchronization issues."
    return

  let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, GL_TIMEOUT_IGNORED) # Wait indefinitely

  if waitResult == 0x911B: # GL_WAIT_FAILED
    error "VirGL: host_write_fence - glClientWaitSync failed. GPU commands may not be flushed."
  elif waitResult == 0x911A: # GL_TIMEOUT_EXPIRED (if not using GL_TIMEOUT_IGNORED)
    warn "VirGL: host_write_fence - glClientWaitSync timed out."

  glDeleteSync(syncObj)

proc host_get_drm_fd(cookie: pointer): cint {.cdecl.} =
  debug "VirGL: host_get_drm_fd called"
  let nodeOpt = getDriNode()
  if nodeOpt.isNone:
    error "VirGL: host_get_drm_fd - DRM node not found for VirGL. Cannot provide DRM FD."
    return -1

  let drmPath = nodeOpt.get.dev
  let fd = open(drmPath, O_RDWR or O_CLOEXEC)
  if fd < 0:
    error "VirGL: host_get_drm_fd - Failed to open DRM node '", drmPath, "'. Error: ", osErrorMsg(osLastError())
    return -1
  else:
    debug "VirGL: host_get_drm_fd - Successfully opened '", drmPath, "', returning fd: ", fd
    return fd

proc host_write_context_fence(cookie: pointer, ctx_id: uint32, ring_idx: uint32, fence_id: uint64): void {.cdecl.} =
  debug "VirGL: host_write_context_fence called with ctx_id: ", ctx_id, ", ring_idx: ", ring_idx, ", fence_id: ", fence_id
  # Similar to host_write_fence, ensure a context is current.
  if hostDisplay == nil:
    error "VirGL: host_write_context_fence - X11 display not initialized."
    return
  # TODO: Add context management based on ctx_id if necessary.

  let syncObj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
  if syncObj == nil:
    error "VirGL: host_write_context_fence - glFenceSync failed."
    return

  let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, GL_TIMEOUT_IGNORED)
  if waitResult == 0x911B: # GL_WAIT_FAILED
    error "VirGL: host_write_context_fence - glClientWaitSync failed."
  elif waitResult == 0x911A: # GL_TIMEOUT_EXPIRED
    warn "VirGL: host_write_context_fence - glClientWaitSync timed out."

  glDeleteSync(syncObj)

# Actual host GLX context creation
proc host_create_gl_context(cookie: pointer, scanout_idx: cint, param: ptr virgl_renderer_gl_ctx_param): virgl_renderer_gl_context {.cdecl.} =
  debug "VirGL: host_create_gl_context called for scanout_idx: ", scanout_idx
  if hostDisplay == nil:
    error "VirGL: host_create_gl_context - Host X11 display not initialized."
    return nil

  if param != nil:
    debug "  Context params: version_major: ", param.major, ", version_minor: ", param.minor, ", shared: ", param.shared

  var visualAttribs: array[10, cint]
  var i = 0
  proc addAttrib(val: cint) = visualAttribs[i] = val; i += 1

  addAttrib(GLX_RGBA)
  addAttrib(GLX_DOUBLEBUFFER)
  addAttrib(GLX_RED_SIZE); addAttrib(8)
  addAttrib(GLX_GREEN_SIZE); addAttrib(8)
  addAttrib(GLX_BLUE_SIZE); addAttrib(8)
  addAttrib(GLX_DEPTH_SIZE); addAttrib(24)
  addAttrib(0)

  let screenNum = XDefaultScreen(hostDisplay)
  let visualInfo = glXChooseVisual(hostDisplay, screenNum, addr(visualAttribs[0]))

  if visualInfo == nil:
    error "VirGL: host_create_gl_context - No suitable GLX visual found. Ensure your X server and GL drivers support the requested attributes."
    return nil
  defer: XFree(visualInfo)

  debug "Chosen GLX visual ID: ", visualInfo.visualid

  let glxCtx = glXCreateContext(hostDisplay, visualInfo, nil, GL_TRUE)
  if glxCtx == nil:
    error "VirGL: host_create_gl_context - Failed to create GLX context. This can be due to driver issues or resource limits."
    return nil

  debug "Created GLX context: ", glxCtx
  return virgl_renderer_gl_context(glxCtx)

# Actual host GLX context destruction
proc host_destroy_gl_context(cookie: pointer, ctx: virgl_renderer_gl_context): void {.cdecl.} =
  debug "VirGL: host_destroy_gl_context called for context: ", ctx
  if hostDisplay == nil:
    error "VirGL: host_destroy_gl_context - Host X11 display not initialized."
    return

  if ctx == nil:
    warn "VirGL: host_destroy_gl_context - Attempted to destroy a nil GLX context."
    return

  let glxCtx = GLXContext(ctx)
  glXDestroyContext(hostDisplay, glxCtx)
  debug "Destroyed GLX context: ", glxCtx

# Actual host GLX make current
proc host_make_current(cookie: pointer, scanout_idx: cint, ctx: virgl_renderer_gl_context): cint {.cdecl.} =
  debug "VirGL: host_make_current called for scanout: ", scanout_idx, ", context: ", ctx
  if hostDisplay == nil:
    error "VirGL: host_make_current - Host X11 display not initialized."
    return -1

  let glxCtx = GLXContext(ctx)

  if defaultHostWindow == 0 and glxCtx != nil :
    let screenNum = XDefaultScreen(hostDisplay)
    let rootWin = XRootWindow(hostDisplay, screenNum)
    defaultHostWindow = XCreateSimpleWindow(hostDisplay, rootWin, 0, 0, 1, 1, 0, 0, 0)
    if defaultHostWindow == 0:
      error "VirGL: host_make_current - Failed to create default X11 window for GLX context."
      # This is a problem, as glXMakeCurrent will likely fail without a drawable.
      # However, allow it to proceed to glXMakeCurrent to see the driver's error.
    else:
      debug "Created default 1x1 X11 window for GLX context: ", defaultHostWindow

  let drawableToUse = if glxCtx == nil: cast[GLXDrawable](0) else: defaultHostWindow

  if glxCtx != nil and drawableToUse == 0:
    debug "VirGL: host_make_current - Context is valid but drawable is 0. This might be okay for surfaceless, but GLX usually needs a drawable."

  if glXMakeCurrent(hostDisplay, drawableToUse, glxCtx) != 0:
    return 0 # Success
  else:
    # Log more selectively to avoid spamming if called frequently with nil context (unbind)
    if glxCtx != nil :
      warn "VirGL: host_make_current - glXMakeCurrent failed for context ", glxCtx, " on drawable ", drawableToUse, ". This can cause rendering failures."
    # else:
      # debug "VirGL: host_make_current - Unbound context (glXMakeCurrent with nil context)" # Usually not an error
    return -1 # Failure

proc placeholder_get_drm_fd(cookie: pointer): cint {.cdecl.} =
  debug "VirGL: placeholder_get_drm_fd called" # Should not be called if host_get_drm_fd is assigned
  return -1

type
  VirglInitError* = object of Exception

proc initVirgl*(drmFd: cint = -1): bool =
  debug "VirGL: Initializing VirGL renderer..."
  var callbacks: virgl_renderer_callbacks
  callbacks.version = VIRGL_RENDERER_CALLBACKS_VERSION

  if hostDisplay == nil:
    hostDisplay = XOpenDisplay(nil)
    if hostDisplay == nil:
      error "VirGL: Failed to open X11 display. Ensure X server is running and DISPLAY environment variable is correctly set."
      raise newException(VirglInitError, "XOpenDisplay failed. Ensure X server is running and DISPLAY is set.")
    else:
      info "VirGL: Successfully opened X11 display: ", hostDisplay

  callbacks.write_fence = host_write_fence
  callbacks.create_gl_context = host_create_gl_context
  callbacks.destroy_gl_context = host_destroy_gl_context
  callbacks.make_current = host_make_current
  callbacks.get_drm_fd = host_get_drm_fd
  callbacks.write_context_fence = host_write_context_fence

  callbacks.get_server_fd = nil
  callbacks.get_egl_display = nil

  let flags = VIRGL_RENDERER_USE_GLX
  debug "VirGL: Attempting to initialize VirGL renderer with flags: ", flags, ", callbacks version: ", callbacks.version
  let result = virgl_renderer_init(nil, flags.cint, addr(callbacks))

  if result != 0:
    error "VirGL: CRITICAL - Failed to initialize VirGL renderer. Error code: ", result, ". Check VirGL/Mesa versions and GPU compatibility. Equinox may not function correctly or will have significantly reduced performance."
    return false

  info "VirGL: VirGL renderer initialized successfully."
  return true
    # This implies that host_write_fence might be called when no context is current.
    # For now, we try to get one, but this might fail if defaultHostWindow isn't set up.
    # The cookie might point to per-context data that we could use to get the right context.
    # This is a simplification; virglrenderer might expect fences to operate on a specific context.
    # For now, using the "default" context made current by host_make_current(nil,0,some_context).
    # This part is tricky: which GL context should this fence be on?
    # Assuming it's the "current" one. If no context is current, this might be an issue.
    # A simple check: if glXGetCurrentContext() == nil, this will likely fail or do nothing.
    # For robust fence operations, a current context is usually required.
    # Let's assume `host_make_current` with a valid context was called before this,
    # or that virglrenderer ensures this. If not, this needs more thought.
    # A minimal check:
    # let currentCtx = glXGetCurrentContext()
    # if currentCtx == nil:
    #   warn "host_write_fence: No GLX context currently bound."
    #   return # Or proceed, hoping for the best / relying on driver leniency
    discard

  let syncObj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0) # 0 for flags
  if syncObj == nil:
    error "host_write_fence: glFenceSync failed."
    # TODO: How to report this error back to virglrenderer?
    return

  # Wait for the fence to ensure commands are flushed. This makes the call synchronous.
  # A very long timeout (1 second) is used here.
  # In a real scenario, managing these sync objects (e.g., deleting them later) is important.
  # For now, wait and delete immediately.
  let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, GL_TIMEOUT_IGNORED) # Wait indefinitely
  # let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000) # 1 sec timeout

  # TODO: Check waitResult (GL_ALREADY_SIGNALED, GL_TIMEOUT_EXPIRED, GL_CONDITION_SATISFIED, GL_WAIT_FAILED)
  # For now, we assume it completes or we proceed anyway after timeout.
  if waitResult == 0x911B: # GL_WAIT_FAILED from glext.h (GLenum usually cint)
    error "host_write_fence: glClientWaitSync failed."

  glDeleteSync(syncObj)
  # debug "host_write_fence: Processed fence_id: ", fence_id

proc host_get_drm_fd(cookie: pointer): cint {.cdecl.} =
  debug "VirGL Callback: host_get_drm_fd called"
  # Check if we already have a cached FD.
  if drmRenderNodeFd >= 0:
    # Need to dup it as virglrenderer might close it.
    # However, the lifecycle is unclear. If virglrenderer uses it temporarily,
    # returning the same FD might be fine if it doesn't close it.
    # For safety, duping is better if the FD is to be long-lived on our side.
    # Or, close the cached one and get a new one each time if short-lived.
    # For now, let's assume virglrenderer doesn't close it, or we reopen.
    # Given typical FD usage, virglrenderer likely expects a new FD it can own/close.
    # So, let's not cache for now, or if we do, dup it.
    # For simplicity of this step: open, return, expect caller to close. No caching.
    discard

  let nodeOpt = getDriNode() # This function finds /dev/dri/renderD*
  if nodeOpt.isSome:
    let drmPath = nodeOpt.get.dev
    # O_CLOEXEC is good practice if Equinox forks other processes that shouldn't inherit this FD.
    let fd = open(drmPath, O_RDWR or O_CLOEXEC)
    if fd < 0:
      error "host_get_drm_fd: Failed to open DRM node ", drmPath, " (errno: ", osLastError(), ")"
      return -1
    else:
      debug "host_get_drm_fd: Successfully opened ", drmPath, ", returning fd: ", fd
      # Store it? If so, when to close it?
      # If virglrenderer is meant to own this FD, we shouldn't close it here.
      # drmRenderNodeFd = fd # Example of caching
      return fd
  else:
    error "host_get_drm_fd: No DRM node found."
    return -1

proc host_write_context_fence(cookie: pointer, ctx_id: uint32, ring_idx: uint32, fence_id: uint64): void {.cdecl.} =
  debug "VirGL Callback: host_write_context_fence called with ctx_id: ", ctx_id, ", ring_idx: ", ring_idx, ", fence_id: ", fence_id
  # This is a more advanced fencing, potentially per-context or per-ring (for Vulkan).
  # For a GLX backend, this can be similar to host_write_fence for now.
  # It might need to ensure operations on a specific context (identified by ctx_id if we map them)
  # are flushed. The current GLX context is implicitly used by glFenceSync.
  # This implies that the correct GLX context should be current when this is called.
  # The `cookie` or `ctx_id` might be used to look up and make current the correct host context.
  # This is a simplification.
  let syncObj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
  if syncObj == nil:
    error "host_write_context_fence: glFenceSync failed."
    return

  let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, GL_TIMEOUT_IGNORED)
  if waitResult == 0x911B: # GL_WAIT_FAILED
    error "host_write_context_fence: glClientWaitSync failed."

  glDeleteSync(syncObj)
  # debug "host_write_context_fence: Processed fence_id: ", fence_id

# Actual host GLX context creation
proc host_create_gl_context(cookie: pointer, scanout_idx: cint, param: ptr virgl_renderer_gl_ctx_param): virgl_renderer_gl_context {.cdecl.} =
  debug "VirGL Callback: host_create_gl_context called for scanout_idx: ", scanout_idx
  if hostDisplay == nil:
    error "Host X11 display not initialized for host_create_gl_context."
    return nil

  if param != nil:
    debug "  Context params: version_major: ", param.major, ", version_minor: ", param.minor, ", shared: ", param.shared
    # TODO: Use these params (major, minor, shared) when creating context if possible.
    # GLX has glXCreateContextAttribsARB for versioned contexts, but that requires extension loading.
    # For now, using basic glXCreateContext.

  # Attributes for glXChooseVisual. Need a visual that supports OpenGL.
  var visualAttribs: array[10, cint] # Array large enough for common attributes + terminator
  var i = 0
  proc addAttrib(val: cint) = visualAttribs[i] = val; i += 1

  addAttrib(GLX_RGBA)
  addAttrib(GLX_DOUBLEBUFFER) # Often requested, though VirGL might manage this
  addAttrib(GLX_RED_SIZE); addAttrib(8)
  addAttrib(GLX_GREEN_SIZE); addAttrib(8)
  addAttrib(GLX_BLUE_SIZE); addAttrib(8)
  addAttrib(GLX_DEPTH_SIZE); addAttrib(24) # Common depth buffer size
  addAttrib(0) # Null terminator for the attribute list

  let screenNum = XDefaultScreen(hostDisplay)
  let visualInfo = glXChooseVisual(hostDisplay, screenNum, addr(visualAttribs[0]))

  if visualInfo == nil:
    error "Failed to choose GLX visual."
    return nil
  defer: XFree(visualInfo) # Free the visual info when done

  debug "Chosen GLX visual ID: ", visualInfo.visualid

  # Create GLX context
  # The `nil` for shared context means no sharing. `param.shared` could be used if it maps to a GLXContext.
  # `GL_TRUE` for direct rendering context.
  let glxCtx = glXCreateContext(hostDisplay, visualInfo, nil, GL_TRUE)
  if glxCtx == nil:
    error "Failed to create GLX context."
    return nil

  debug "Created GLX context: ", glxCtx
  return virgl_renderer_gl_context(glxCtx) # Cast GLXContext to virgl_renderer_gl_context (pointer)

# Actual host GLX context destruction
proc host_destroy_gl_context(cookie: pointer, ctx: virgl_renderer_gl_context): void {.cdecl.} =
  debug "VirGL Callback: host_destroy_gl_context called for context: ", ctx
  if hostDisplay == nil:
    error "Host X11 display not initialized for host_destroy_gl_context."
    return

  if ctx == nil:
    warn "Attempted to destroy a nil GLX context."
    return

  let glxCtx = GLXContext(ctx) # Cast back from virgl_renderer_gl_context
  glXDestroyContext(hostDisplay, glxCtx)
  debug "Destroyed GLX context: ", glxCtx

# Actual host GLX make current
proc host_make_current(cookie: pointer, scanout_idx: cint, ctx: virgl_renderer_gl_context): cint {.cdecl.} =
  # debug "VirGL Callback: host_make_current called for scanout: ", scanout_idx, ", context: ", ctx
  if hostDisplay == nil:
    # error "Host X11 display not initialized for host_make_current." # Too noisy
    return -1

  let glxCtx = GLXContext(ctx) # Cast back

  # VirGL often uses surfaceless rendering or manages its own drawables (scanouts).
  # For now, we need a drawable. If defaultHostWindow is not set, try to create one.
  # This is a very basic drawable management, likely needs refinement for VirGL.
  if defaultHostWindow == 0 and glxCtx != nil : # Only create window if context is not nil
    let screenNum = XDefaultScreen(hostDisplay)
    let rootWin = XRootWindow(hostDisplay, screenNum)
    # Create a minimal 1x1 window.
    # In a real scenario, this might be a Pbuffer or a window tied to a scanout.
    defaultHostWindow = XCreateSimpleWindow(hostDisplay, rootWin, 0, 0, 1, 1, 0, 0, 0)
    debug "Created default 1x1 X11 window for GLX context: ", defaultHostWindow

  # If context is nil, we are unbinding. Use GLX_NONE for drawable.
  let drawableToUse = if glxCtx == nil: cast[GLXDrawable](0) else: defaultHostWindow

  if glxCtx != nil and drawableToUse == 0:
    # error "No drawable available for host_make_current with a valid context." # Can be noisy
    # This state means we want to make a context current, but have no window/pbuffer.
    # For surfaceless EGL, this is fine, but GLX usually needs a drawable.
    # Depending on VirGL flags (e.g. surfaceless), this might be okay or an issue.
    # For now, we proceed, glXMakeCurrent might fail if drawable is invalid for the context.
    # It might also be that VirGL expects us to create a Pbuffer based on scanout_idx or similar.
    # This part is crucial and needs to align with how VirGL expects scanouts to be handled.
    debug "host_make_current: context is valid but drawable is 0. Proceeding, may fail."


  if glXMakeCurrent(hostDisplay, drawableToUse, glxCtx) != 0: # Non-zero is success for glXMakeCurrent in some bindings, zero in others. Standard is True (non-zero) for success.
    # trace "Made GLX context ", glxCtx, " current on drawable ", drawableToUse # trace is very verbose
    return 0 # Success
  else:
    if glxCtx != nil: # Only log error if we were trying to make a valid context current
      warn "glXMakeCurrent failed for context ", glxCtx, " on drawable ", drawableToUse
    return -1 # Failure

proc placeholder_get_drm_fd(cookie: pointer): cint {.cdecl.} =
  debug "VirGL Callback: get_drm_fd called, cookie: ", cookie
  # TODO: Return a valid DRM file descriptor if needed, or -1 if not applicable/available.
  return -1

type
  VirglInitError* = object of Exception

proc initVirgl*(drmFd: cint = -1): bool =
  var callbacks: virgl_renderer_callbacks
  callbacks.version = VIRGL_RENDERER_CALLBACKS_VERSION

  # Initialize X11 display if not already done
  if hostDisplay == nil:
    hostDisplay = XOpenDisplay(nil) # Open default display
    if hostDisplay == nil:
      error "Failed to open X11 display."
      raise newException(VirglInitError, "XOpenDisplay failed. Ensure X server is running and DISPLAY is set.")
    else:
      info "Successfully opened X11 display: ", hostDisplay
      # Clean up display on application exit? This is tricky with shared library usage.
      # For now, keep it open. LXC container context means it closes on container exit.

  callbacks.write_fence = host_write_fence
  callbacks.create_gl_context = host_create_gl_context
  callbacks.destroy_gl_context = host_destroy_gl_context
  callbacks.make_current = host_make_current
  callbacks.get_drm_fd = host_get_drm_fd
  callbacks.write_context_fence = host_write_context_fence

  # Explicitly set unused Wayland/EGL specific callbacks to nil for clarity and safety.
  # These are not used in the current GLX-based backend.
  callbacks.get_server_fd = nil   # For Wayland integration (external server fd)
  callbacks.get_egl_display = nil # For EGL specific interop

  # TODO: Review the full virgl_renderer_callbacks struct definition from
  # pkg/virglrenderer and ensure all other non-implemented members are also
  # explicitly set to nil if they aren't defaulted to nil by Nim struct initialization
  # or by the binding itself. Examples:
  # callbacks.get_caps = nil
  # callbacks.resource_create = nil
  # callbacks.resource_attach_iov = nil
  # callbacks.resource_detach_iov = nil
  # callbacks.context_create = nil # (if different from gl_context_create)
  # callbacks.context_destroy = nil # (if different from gl_context_destroy)
  # callbacks.submit_cmd = nil
  # callbacks.resource_map = nil
  # callbacks.resource_unmap = nil
  # callbacks.create_gl_context_with_flags = nil # More advanced context creation
  # ... and others as defined in virglrenderer.h.
  # For this subtask, only get_server_fd and get_egl_display are explicitly set.

  let flags = VIRGL_RENDERER_USE_GLX
  debug "Attempting to initialize VirGL renderer with flags: ", flags, ", callbacks version: ", callbacks.version
  let result = virgl_renderer_init(nil, flags.cint, addr(callbacks))

  if result != 0:
    error "Failed to initialize VirGL renderer. Error code: ", result
    # Clean up X display if we opened it and init failed?
    # if hostDisplay != nil:
    #   XCloseDisplay(hostDisplay)
    #   hostDisplay = nil
    return false

  info "VirGL renderer initialized successfully."
  # If defaultHostWindow was created and is no longer needed after init (e.g. for tests), destroy it.
  # However, it's likely needed for ongoing make_current calls.
  # if defaultHostWindow != 0:
  #   XDestroyWindow(hostDisplay, defaultHostWindow)
  #   defaultHostWindow = 0
  return true
