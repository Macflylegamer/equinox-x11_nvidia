import std/[os, logging, options, strutils, sequtils, tables]
import pkg/[glob]

const UnsupportedGPUDrivers*: seq[string] = @[] # Explicitly typed empty sequence

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
import ../bindings/virgl # Corrected import path for local virglrenderer bindings

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
  hostDisplay {.threadvar.}: ptr DisplayX
  # A simple window for GLX contexts if needed as a default drawable.
  # VirGL might manage its own scanout surfaces, this is a fallback/default.
  defaultHostWindow {.threadvar.}: WindowX
  # TODO: Proper management of this window (creation/destruction)
  drmRenderNodeFd {.threadvar.}: cint

# VirGL Host Callbacks Implementation

proc host_write_fence(cookie: pointer, fence_id: uint32): void {.cdecl.} =
  debug "VirGL: host_write_fence called, fence_id: ", fence_id
  if hostDisplay == nil:
    error "VirGL: host_write_fence - X11 display not initialized."
    return
  # Note: For robust fence operations, a current GL context is typically required.
  # virglrenderer should ensure the appropriate context is current before calling this.
  # The current implementation assumes this condition is met.

  let syncObj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0) # 0 for flags
  if syncObj == nil:
    error "VirGL: host_write_fence - glFenceSync failed. This can lead to rendering synchronization issues."
    return

  let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, uint64(GL_TIMEOUT_IGNORED)) # Wait indefinitely

  if waitResult == 0x911B: # GL_WAIT_FAILED
    error "VirGL: host_write_fence - glClientWaitSync failed. GPU commands may not be flushed."
  elif waitResult == 0x911A: # GL_TIMEOUT_EXPIRED (if not using GL_TIMEOUT_IGNORED)
    warn "VirGL: host_write_fence - glClientWaitSync timed out."

  glDeleteSync(syncObj)

proc host_get_drm_fd(cookie: pointer): cint {.cdecl.} =
  debug "VirGL: host_get_drm_fd called"
  # This implementation opens a new FD on each call, assuming virglrenderer
  # will close it. If caching is desired, proper duping and lifecycle management
  # of the cached FD would be needed (e.g. store in drmRenderNodeFd and dup before return).
  let nodeOpt = getDriNode()
  if nodeOpt.isNone:
    error "VirGL: host_get_drm_fd - DRM node not found. Cannot provide DRM FD."
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
  if hostDisplay == nil:
    error "VirGL: host_write_context_fence - X11 display not initialized."
    return
  # Note: This callback might imply operations on a specific context (ctx_id).
  # The current implementation uses glFenceSync on the currently bound GLX context.
  # TODO: A more advanced backend might need to map ctx_id to a host GLXContext and make it current.

  let syncObj = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
  if syncObj == nil:
    error "VirGL: host_write_context_fence - glFenceSync failed."
    return

  let waitResult = glClientWaitSync(syncObj, GL_SYNC_FLUSH_COMMANDS_BIT, uint64(GL_TIMEOUT_IGNORED))
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
    debug "  Context params: version_major: ", param.major_ver, ", version_minor: ", param.minor_ver, ", shared: ", param.shared
    # TODO: Use context creation parameters (param.major_ver, param.minor_ver, param.shared)
    #       e.g., by using glXCreateContextAttribsARB if available, for specific GL versions.

  # Attributes for glXChooseVisual.
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
  defer: discard XFree(visualInfo)

  debug "Chosen GLX visual ID: ", visualInfo.visualid

  let glxCtx = glXCreateContext(hostDisplay, visualInfo, nil, GL_TRUE)
  if glxCtx == nil:
    error "VirGL: host_create_gl_context - Failed to create GLX context. This can be due to driver issues or resource limits."
    return nil

  debug "Created GLX context: ", cast[BiggestInt](glxCtx)
  return virgl_renderer_gl_context(glxCtx)

# Actual host GLX context destruction
proc host_destroy_gl_context(cookie: pointer, ctx: virgl_renderer_gl_context): void {.cdecl.} =
  debug "VirGL: host_destroy_gl_context called for context: ", cast[BiggestInt](ctx)
  if hostDisplay == nil:
    error "VirGL: host_destroy_gl_context - Host X11 display not initialized."
    return

  if ctx == nil:
    warn "VirGL: host_destroy_gl_context - Attempted to destroy a nil GLX context."
    return

  let glxCtx = GLXContext(ctx)
  glXDestroyContext(hostDisplay, glxCtx)
  debug "Destroyed GLX context: ", cast[BiggestInt](glxCtx)

# Actual host GLX make current
proc host_make_current(cookie: pointer, scanout_idx: cint, ctx: virgl_renderer_gl_context): cint {.cdecl.} =
  # This log can be very verbose; `trace` level might be more appropriate in the long term.
  debug "VirGL: host_make_current called for scanout: ", scanout_idx, ", context: ", cast[BiggestInt](ctx)
  if hostDisplay == nil:
    error "VirGL: host_make_current - Host X11 display not initialized."
    return -1

  let glxCtx = GLXContext(ctx)

  if defaultHostWindow == 0 and glxCtx != nil :
    let screenNum = XDefaultScreen(hostDisplay)
    let rootWin = XRootWindow(hostDisplay, screenNum)
    # Create a minimal 1x1 window to act as a default drawable.
    defaultHostWindow = XCreateSimpleWindow(hostDisplay, rootWin, 0, 0, 1, 1, 0, 0, 0)
    if defaultHostWindow == 0:
      error "VirGL: host_make_current - Failed to create default X11 window for GLX context."
      # Proceeding, but glXMakeCurrent will likely fail without a valid drawable.
    else:
      debug "Created default 1x1 X11 window for GLX context: ", defaultHostWindow

  let drawableToUse = if glxCtx == nil: cast[GLXDrawable](0) else: defaultHostWindow

  if glxCtx != nil and drawableToUse == 0:
    # This state means we want to make a context current, but have no window/pbuffer.
    # GLX usually needs a drawable. Depending on VirGL flags (e.g. surfaceless), this might be okay or an issue.
    debug "VirGL: host_make_current - Context is valid but drawable is 0. This might be okay for surfaceless rendering modes."

  if glXMakeCurrent(hostDisplay, drawableToUse, glxCtx) != 0:
    return 0 # Success
  else:
    # Log more selectively to avoid spamming if called frequently with nil context (unbind)
    if glxCtx != nil :
      warn "VirGL: host_make_current - glXMakeCurrent failed for context ", cast[BiggestInt](glxCtx), " on drawable ", cast[BiggestInt](drawableToUse), ". This can cause rendering failures."
    # else:
      # debug "VirGL: host_make_current - Unbound context (glXMakeCurrent with nil context)" # Usually not an error
    return -1 # Failure

proc placeholder_get_drm_fd(cookie: pointer): cint {.cdecl.} =
  debug "VirGL: placeholder_get_drm_fd called" # Should not be called if host_get_drm_fd is assigned
  return -1

type
  VirglInitError* = object of Exception

proc initVirgl*(drmFd: cint = -1): bool =
  debug "VirGL: Initializing VirGL renderer..." # 2 spaces
  var callbacks: virgl_renderer_callbacks      # 2 spaces
  callbacks.version = VIRGL_RENDERER_CALLBACKS_VERSION # 2 spaces

  # Initialize X11 display if not already done
  if hostDisplay == nil:                       # 2 spaces
    hostDisplay = XOpenDisplay(nil)            # 4 spaces
    if hostDisplay == nil:                     # 4 spaces
      error "VirGL: Failed to open X11 display. Ensure X server is running and DISPLAY environment variable is correctly set." # 6 spaces
      raise newException(VirglInitError, "XOpenDisplay failed. Ensure X server is running and DISPLAY is set.") # 6 spaces
    else:                                     # 4 spaces
      info "VirGL: Successfully opened X11 display: ", cast[BiggestInt](hostDisplay) # 6 spaces
      # Clean up display on application exit? This is tricky with shared library usage. # 6 spaces
      # For now, keep it open. LXC container context means it closes on container exit.  # 6 spaces

  # Assign VirGL host callbacks
  callbacks.write_fence = host_write_fence    # 2 spaces
  callbacks.create_gl_context = host_create_gl_context # 2 spaces
  callbacks.destroy_gl_context = host_destroy_gl_context # 2 spaces
  callbacks.make_current = host_make_current  # 2 spaces
  callbacks.get_drm_fd = host_get_drm_fd      # 2 spaces
  callbacks.write_context_fence = host_write_context_fence # 2 spaces

  # Explicitly set unused Wayland/EGL specific callbacks to nil
  callbacks.get_server_fd = nil               # 2 spaces
  callbacks.get_egl_display = nil             # 2 spaces

  # TODO: Review the full virgl_renderer_callbacks struct definition from the
  # `../bindings/virgl` module. Ensure all other non-implemented members are
  # explicitly set to nil if they are not automatically zero-initialized or if
  # explicit assignment is preferred for clarity. Examples of other callbacks:
  # - get_caps
  # - resource_create, resource_attach_iov, resource_detach_iov
  # - context_create, context_destroy (if different from gl_context versions)
  # - submit_cmd
  # - resource_map, resource_unmap (critical for shared memory/DMA buf)
  # - create_gl_context_with_flags (more advanced context creation)

  let flags = VIRGL_RENDERER_USE_GLX          # 2 spaces
  debug "VirGL: Attempting to initialize VirGL renderer with flags: ", flags, ", callbacks version: ", callbacks.version # 2 spaces
  let result = virgl_renderer_init(nil, flags.cint, addr(callbacks)) # 2 spaces

  if result != 0:                             # 2 spaces
    error "VirGL: CRITICAL - Failed to initialize VirGL renderer. Error code: ", result, ". Check VirGL/Mesa versions and GPU compatibility. Equinox may not function correctly or will have significantly reduced performance." # 4 spaces
    return false                               # 4 spaces

  info "VirGL: VirGL renderer initialized successfully." # 2 spaces
  return true                                 # 2 spaces
