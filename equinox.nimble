# Package

version = "0.1.6"
author = "xTrayambak"
description = "Equinox is a runtime for Roblox on Linux."
license = "MIT"
srcDir = "src"
bin = @["equinox", "equinox_gui"]

# Dependencies

requires "nim >= 2.0.0"
requires "colored_logger >= 0.1.0"
requires "nimsimd >= 1.3.2"
requires "curly >= 1.1.1"
requires "jsony >= 1.1.5"
requires "glob >= 0.11.3"
requires "pretty >= 0.2.0"
requires "mimalloc >= 0.3.1"
requires "noise >= 0.1.10"
requires "crunchy >= 0.1.11"
requires "zippy >= 0.10.16"
requires "zip >= 0.3.1"
requires "owlkettle >= 3.0.0"
requires "db_connector >= 0.1.0"
requires "https://github.com/equinoxhq/libgbinder-nim >= 0.1.0"
requires "discord_rpc >= 0.2.0"
requires "shakar >= 0.1.0"
requires "https://github.com/ferus-web/sanchar >= 2.0.2"
requires "results >= 0.5.1"
requires "libcurl >= 1.0.0"

when defined(equinox):
  nimflags.path(srcDir / "equinox.nim").add("--header")
