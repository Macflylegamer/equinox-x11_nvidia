## kawaii-est VirGL bindings you'll ever find ^w^
## Copyright (C) 2025 Trayambak Rai and the EquinoxHQ team
import std/[posix]

{.passC: gorge("pkg-config --silence-errors --cflags virglrenderer").}
{.passL: gorge("pkg-config --silence-errors --libs virglrenderer").}

template def(val: untyped) =
  var `val`* {.importc, header: "<virgl/virglrenderer.h>".}: int32

{.push importc, header: "<virgl/virgl-version.h>".}
var
  VIRGL_MAJOR_VERSION*: int32
  VIRGL_MINOR_VERSION*: int32
  VIRGL_MICRO_VERSION*: int32
{.pop.}

{.push header: "<virgl/virglrenderer.h>".}
type
  virgl_box* {.importc: "struct virgl_box".} = object
  iovec* {.importc: "struct iovec".} = object

  virgl_renderer_gl_context* {.importc.} = pointer
  virgl_renderer_gl_ctx_param* {.importc: "struct virgl_renderer_gl_ctx_param".} = object
    version*: int32
    shared*: bool
    major_ver*: int32
    minor_ver*: int32
    compat_ctx*: int32

  virgl_renderer_callbacks* {.importc: "struct virgl_renderer_callbacks".} = object
    version*: int32
    write_fence*: proc(cookie: pointer, fence: uint32): void {.cdecl.}
    create_gl_context*: proc(
      cookie: pointer, scanout_idx: int32, param: ptr virgl_renderer_gl_ctx_param
    ): virgl_renderer_gl_context {.cdecl.}
    destroy_gl_context*:
      proc(cookie: pointer, ctx: virgl_renderer_gl_context): void {.cdecl.}
    make_current*: proc(
      cookie: pointer, scanout_idx: int32, ctx: virgl_renderer_gl_context
    ): int32 {.cdecl.}
    get_drm_fd*: proc(cookie: pointer): cint {.cdecl.}
    write_context_fence*: proc(
      cookie: pointer, ctx_id: uint32, ring_idx: uint32, fence_id: uint64
    ): void {.cdecl.}
    get_server_fd*: proc(cookie: pointer, version: uint32): cint {.cdecl.}
    get_egl_display*: proc(cookie: pointer): pointer {.cdecl.}

def VIRGL_RENDERER_CALLBACKS_VERSION
def VIRGL_RENDERER_USE_EGL
def VIRGL_RENDERER_THREAD_SYNC
def VIRGL_RENDERER_USE_GLX
def VIRGL_RENDERER_USE_SURFACELESS
def VIRGL_RENDERER_USE_GLES
def VIRGL_RENDERER_USE_EXTERNAL_BLOB
def VIRGL_RENDERER_VENUS
def VIRGL_RENDERER_NO_VIRGL
def VIRGL_RENDERER_ASYNC_FENCE_CB
def VIRGL_RENDERER_RENDER_SERVER
def VIRGL_RENDERER_DRM
def VIRGL_RENDERER_UNSTABLE_APIS
def VIRGL_RENDERER_USE_VIDEO
def VIRGL_RENDERER_D3D11_SHARE_TEXTURE
def VIRGL_RENDERER_COMPAT_PROFILE
def VIRGL_RENDERER_USE_GUEST_VRAM

{.push importc.}
proc virgl_renderer_init*(
  cookie: pointer, flags: int32, cb: ptr virgl_renderer_callbacks
): int32

proc virgl_renderer_poll*(): void
{.pop.}

{.pop.}
