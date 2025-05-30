import mimalloc/config

# Potential linker flags for X11/GLX/Epoxy if used directly for VirGL callbacks.
# These would be necessary if the VirGL callback implementations (e.g., in src/container/gpu.nim)
# make direct calls to X11, GLX, or Epoxy functions for host OpenGL context management.
# The virglrenderer library itself might link some of these, but direct usage from Equinox code
# would require explicit linking.

# One approach is to add them globally here:
# when defined(linux) and defined(equinox_nvidia_x11_virgl): # Using a hypothetical define to enable
#   # Order might matter. Typically, libraries are listed after the code that uses them.
#   # `gl` usually covers GLX. `epoxy` if used for GL function loading.
#   {.passL: gorge("pkg-config --libs x11 xext gl epoxy").}
#   # If not using pkg-config or for more fine-grained control:
#   # {.passL: "-lX11 -lXext -lGL -lpthread".} # Add -lepoxy if epoxy is used

# Alternatively, and often preferred for modularity, these linking pragmas can be placed
# directly within the .nim file that implements the VirGL callbacks (e.g., src/container/gpu.nim)
# using:
#   {.compile: "<some_C_header_for_X11_or_GLX.h>".}
#   {.passL: "-lX11 -lGL".} # etc.
# This keeps dependencies localized to the module that needs them.

# For now, these are commented out as the actual callback implementation
# will determine the precise linking requirements.
