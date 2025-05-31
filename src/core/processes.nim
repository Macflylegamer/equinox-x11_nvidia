import std/[os, options, strutils]

proc pidof*(name: string): Option[uint] =
  for kind, dir in walkDir("/proc"):
    if kind != pcDir:
      continue
    if not fileExists(dir / "cmdline"):
      continue

    let target = readFile(dir / "cmdline")
    # debug "equinox: " & dir & ": " & target

    if target.contains(name):
      let pid = splitPath(dir).tail.parseUint()
      # procTraversalCache.add(CachedPid(name: name, pid: pid))
      return some(pid)
