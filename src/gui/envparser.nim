import std/[strformat, os, logging]
import ../[argparser]

type XdgEnv* = object
  runtimeDir*: string
  waylandDisplay*: string
  user*: string
  equinoxPath*: string

const equinoxBin* {.strdefine.} = ""

# TODO: refactor to remove input
proc getXdgEnv*(input: Input): XdgEnv =
  let equinoxPath =
    if (let env = getEnv("EQUINOX_BIN"); env != ""):
      if not fileExists(env):
        error &"equinox: EQUINOX_BIN environment variable is defined, but '{env}' is not exist"
        quit(1)
      env
    elif equinoxBin != "":
      if not fileExists(equinoxBin):
        error &"equinox: equinox path is defined at compile-time, but '{equinoxBin}' is not exist"
        quit(1)
      equinoxBin
    elif (let bin = findExe("equinox"); bin.len > 0):
      bin
    elif (let bin = getCurrentDir() / "equinox"; fileExists(bin)):
      getCurrentDir() / "equinox"
    else:
      error &"equinox: cannot find equinox bin, is your installation broken?"
      quit(1)

  XdgEnv(
    runtimeDir: getEnv("XDG_RUNTIME_DIR"),
    waylandDisplay: getEnv("WAYLAND_DISPLAY"),
    user: getEnv("USER"),
    equinoxPath: equinoxPath,
  )
