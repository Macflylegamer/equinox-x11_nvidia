import std/[os, options, logging, strutils, posix, tables, json, strformat]
import ../container/gpu # For initVirgl
import
  ../container/[lxc, drivers, platform, network, rootfs, app_config, fflags, settings]
import pkg/[discord_rpc, shakar]
import ../argparser
import ../container/utils/[exec, mount], ../container/paths
import ./event_manager/[types, dispatcher]
import ./[discord_rpc, fflag_patches, roblox_logs, processes]

proc showUI*(user: string, launch: bool = true) =
  var platform = getIPlatformService(user)
  if launch:
    platform.launchApp("com.roblox.client")

  platform.setProperty("waydroid.active_apps", "com.roblox.client")

proc startRobloxClient*(user: string, platform: var IPlatform) =
  while isEmptyOrWhitespace(&readOutput("pidof", "com.roblox.client")):
    # FIXME: please don't do this
    platform.launchApp("com.roblox.client")
    sleep(100)

  startLogWatcher(user)

proc processEvents*(dispatcher: var EventDispatcher, rpc: DiscordRPC) =
  let pid = pidof("com.roblox.client")
  if !pid:
    info "equinox: com.roblox.client has exited, setting dispatcher flag to false"
    dispatcher.running = false
    return

  let (event, exhausted) = dispatcher.poll()
  if exhausted:
    return

  case event.kind
  of Event.GameJoin:
    info "equinox: user joined game; id=" & event.id
    handleGameRPC(rpc, event.id)
  of Event.GameLeave:
    info "equinox: user left game."
    handleIdleRPC(rpc)
  of Event.BloxstrapRPC:
    info "equinox: received BloxstrapRPC payload"
    handleBloxstrapRPC(rpc, event.payload)
  of Event.RobloxClose:
    info "equinox: roblox has exited; flagging dispatcher state as exited"
    dispatcher.running = false

proc patchOutOSK*() =
  debug "equinox: trying to uninstall OSK"

  while not isServiceOn("package"):
    continue

  discard &runCmdInContainer("pm uninstall --user 0 com.android.inputmethod.latin")

proc startAndroidRuntime*(input: Input, launchRoblox: bool = true) =
  stderr.writeLine "Debug: run.nim - startAndroidRuntime() called."
  info "equinox: starting android runtime" # Original info log
  debug "equinox: starting prep for android runtime" # Original debug log

  destroyAllLogs(&input.flag("user"))
  mountRootfs(input, getImagesPath())
  discard probeBinderDriver()

  var settings = loadAppConfig(input)

  debug "equinox: applying config"

  if *settings.maxFps:
    settings.fflags["DFIntTaskSchedulerTargetFps"] = newJInt(int(&settings.maxFps))

  settings.fflags["FFlagUserFyosDetectionHorseFly"] = newJBool(true) # for shy :3

  applyFflagPatches(settings.fflags)
  setFflags(input, settings.fflags)
  generateSessionLxcConfig(input)

  stderr.writeLine "Debug: run.nim - startAndroidRuntime() - Attempting to initialize VirGL..."
  try:
    if not initVirgl(): # initVirgl is from ../container/gpu
      stderr.writeLine "FATAL ERROR in startAndroidRuntime(): initVirgl() returned false. Equinox may not function correctly or will have significantly reduced performance."
      # Not quitting here allows container to start for debugging or if VirGL isn't strictly critical for some non-Roblox use case.
      # quit(1)
    else:
      stderr.writeLine "Debug: run.nim - startAndroidRuntime() - initVirgl() succeeded."
  except Exception as e:
    stderr.writeLine "FATAL CRASH in startAndroidRuntime() during/after initVirgl():
Exception Type: " & $e.name & "
Message: " & e.msg & "
StackTrace:
" & e.getStackTrace()
    quit(1) # Definitely quit if initVirgl crashes

  stderr.writeLine "Debug: run.nim - startAndroidRuntime() - Proceeding to start LXC container..."

  var dispatcher = initEventDispatcher()
  dispatcher.running = true

  if getLxcStatus() == "RUNNING":
    stopLxcContainer()

  startLxcContainer(input)
  stderr.writeLine "Debug: run.nim - startAndroidRuntime() - startLxcContainer() finished."
  waitForContainerBoot()
  stderr.writeLine "Debug: run.nim - startAndroidRuntime() - waitForContainerBoot() finished."

  var platform = getIPlatformService(&input.flag("user"))
  platform.setProperty("waydroid.active_apps", "com.roblox.client")

  settingsPut("system", "dim_screen", false) # Don't dim the screen.
  settingsPut("system", "screen_brightness", 100)
  settingsPut("system", "screen_brightness_float", 1)
  settingsPut("system", "volume_notification", 0)
  settingsPut("system", "volume_ring", 0)
  settingsPut("system", "volume_system", 0)
  settingsPut("system", "volume_alarm", 0)
  settingsPut("system", "ringtone_set", false)
  settingsPut("system", "notification_sound_set", false)
  settingsPut("system", "notification_light_pulse", false)
  settingsPut("system", "hide_rotation_lock_toggle_for_accessibility", true)
  settingsPut("system", "hearing_aid", false)
    # UD method (set it to true for the funnies)
  settingsPut("system", "theater_mode_on", true) # Make sure no Android garbage shows up
  settingsPut("secure", "screensaver_enabled", false)
  settingsPut("secure", "volume_hush_gesture", false)
  settingsPut("secure", "sysui_nav_bar", false)
  settingsPut("global", "policy_control", "immersive.status=*")

  if launchRoblox:
    startRobloxClient(&input.flag("user"), platform)
    patchOutOSK()

    putEnv("XDG_RUNTIME_DIR", &input.flag("xdg-runtime-dir"))
      # Fixes a crash with Discord RPC as we don't have XDG_RUNTIME_DIR in the environment 
      # since we're running as root.
    var rpc = newDiscordRpc(RPCApplicationId)

    if settings.discordRpc:
      debug "equinox: RPC is enabled"
      try:
        let res = rpc.connect()
        debug "equinox: connected to Discord RPC."
        debug "equinox: CDN host = " & res.config.cdnHost & ", API endpoint = " &
          res.config.apiEndpoint & ", env = " & res.config.environment
        debug "equinox: logged in as " & res.user.username & " (" & $res.user.id & ")"
      except CatchableError as exc:
        debug "equinox: cannot connect to Discord RPC: " & exc.msg
        rpc = nil
    else:
      debug "equinox: RPC is disabled"
      rpc = nil

    rpc.handleIdleRPC()

    while dispatcher.running:
      sleep(350)
      processEvents(dispatcher, rpc)

    info "equinox: app deinit started"
    stopLogWatcher()
    stopNetworkService()
    stopLxcContainer()
    umountAll(getRootfsPath())
    info "equinox: app cleanup completed gracefully"

type PlaceURI* = string

proc launchRobloxGame*(input: Input, id: PlaceURI | string) =
  info "equinox: sending VIEW intent to roblox client"

  if getLxcStatus() != "RUNNING":
    startAndroidRuntime(input, launchRoblox = false)
  else:
    showUI(&input.flag("user"), launch = false)

  var platform = getIPlatformService(&input.flag("user"))
  platform.launchIntent("android.intent.action.VIEW", "roblox://placeId=" & $id)
  platform.setProperty("waydroid.active_apps", "com.roblox.client")
