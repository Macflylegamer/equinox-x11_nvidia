## Launcher GUI
import std/[os, browsers, logging, options, osproc, posix, strutils]
import pkg/owlkettle, pkg/owlkettle/[adw], pkg/[shakar]
import ../container/network, ../core/[forked_ipc, state], ./[common, envparser], ../argparser

type LauncherMagic {.pure, size: sizeof(uint8).} = enum
  Launch = 0 ## Launch Equinox.
  Halt = 1 ## Halt Equinox.
  Die = 2 ## Kill yourself.
  GSM = 3

viewable Launcher:
  title:
    string = "Equinox"
  active:
    bool = false
  sensitive:
    bool = true
  toggle:
    bool
  offset:
    tuple[x, y: int] = (0, 0)
  sizeRequest:
    tuple[x, y: int] = (-1, -1)
  position:
    PopoverPosition = PopoverBottom

  env:
    XdgEnv

  sock:
    cint

template settingsMenu(): Widget =
  Window()

proc networkCheck(app: LauncherState): bool =
  let
    device = getNetworkDevice()
    offline = !device or not isOnline(&device)

  result = offline

  if offline:
    discard app.open:
      gui:
        Window:
          defaultSize = (480, 320)
          title = "You are offline."

          Clamp:
            maximumSize = 500
            margin = 12

            Box:
              orient = OrientY
              spacing = 12

              Icon:
                name = "network-cellular-disabled-symbolic"
                pixelSize = 200

              Label:
                text =
                  "<span size=\"large\">Equinox could not find an active network connection. Without it, <b>Roblox won't run.</b></span>"
                useMarkup = true

proc googleAuthPhase(app: LauncherState) =
  var state = getAppState()
  if not state.promptGsm:
    return

  state.promptGsm = false
  state.save()
  app.sock.send(LauncherMagic.GSM)

  discard app.open:
    gui:
      Window:
        defaultSize = (480, 320)
        title = "Google Authentication"

        Clamp:
          maximumSize = 500
          margin = 12

          Box:
            orient = OrientY
            spacing = 12

            Label:
              text =
                "Your browser has been opened up with the Google Device Certification website. Go ahead and paste the code stored in your clipboard."

method view(app: LauncherState): Widget =
  result = gui:
    Window:
      defaultSize = (500, 400)
      title = app.title
      HeaderBar {.addTitlebar.}:
        style = [HeaderBarFlat]

        MenuButton {.addRight.}:
          icon = "preferences-other-symbolic"
          style = [ButtonFlat]

        MenuButton {.addLeft.}:
          icon = "open-menu"
          style = [ButtonFlat]

          PopoverMenu:
            sensitive = app.sensitive
            sizeRequest = app.sizeRequest
            offset = app.offset
            position = app.position

            Box {.name: "main".}:
              orient = OrientY
              margin = 4
              spacing = 3

              ModelButton:
                text = "About Equinox"
                proc clicked() =
                  openAboutMenu(app)

      Clamp:
        maximumSize = 500
        margin = 12

        Box:
          orient = OrientY
          spacing = 12

          PreferencesGroup {.expand: false.}:
            #title = app.title
            #description = "app.description"

            ActionRow:
              title = "Make sure to follow the README instructions."
              subtitle = "This software is experimental and may break."

            ActionRow:
              title =
                "Please make sure that you agree to the EquinoxHQ Terms of Service before you begin."
              subtitle = "The Equinox team is not responsible for any damages."

            Label:
              text = "Welcome to the Equinox launcher."
              margin = 24

          Box {.hAlign: AlignCenter, vAlign: AlignCenter.}:
            orient = OrientX
            spacing = 12

            Button:
              style = [ButtonPill, ButtonSuggested]
              text = "Launch Roblox"
              tooltip = "This will start Roblox through Equinox."
              proc clicked() =
                googleAuthPhase(app)

                if networkCheck(app):
                  return

                app.sock.send(LauncherMagic.Launch)

            Button:
              style = [ButtonPill, ButtonDestructive]
              text = "Stop Equinox"
              tooltip = "Gracefully shut down the Equinox container."
              proc clicked() =
                app.sock.send(LauncherMagic.Halt)

proc waitForCommands*(env: XdgEnv, fd: cint) {.noReturn.} =
  stderr.writeLine "Debug: launcher.nim - waitForCommands() - Child (PID: " & $getpid() & ") waiting for IPC."
  debug "launcher/child: waiting for commands" # Original debug log

  var running = true
  while running:
    debug "launcher/child: waiting for opcode"
    let op = fd.receive(LauncherMagic)
    debug "launcher/child: opcode -> " & $op

    case op
    of LauncherMagic.Launch:
      stderr.writeLine "Debug: launcher.nim - waitForCommands() - Received Launch command. Forking for 'equinox run'..."
      let cmd =
        findExe("pkexec") & ' ' & env.equinoxPath & " run --xdg-runtime-dir:" &
        env.runtimeDir & " --wayland-display:" & env.waylandDisplay & " --user:" &
        env.user & " --uid:" & $getuid() & " --gid:" & $getgid()

      debug "launcher/child: cmd -> " & cmd # Original debug log
      let pid = fork()

      if pid == 0:
        stderr.writeLine "Debug: launcher.nim - waitForCommands() - Grandchild process (PID: " & $getpid() & ") executing 'equinox run'..."
        debug "launcher/child: we're the forked child" # Original debug log
        discard execCmd(cmd)
        quit(0)
      else:
        debug "launcher/child: we're the parent"
    of LauncherMagic.Halt:
      let cmd = findExe("pkexec") & ' ' & env.equinoxPath & " halt --force"
      debug "launcher/child: cmd -> " & cmd

      discard execCmd(cmd)
    of LauncherMagic.GSM:
      let (output, code) =
        execCmdEx("pkexec " & env.equinoxPath & " get-gsf-id --user:" & env.user)

      if code == 0:
        discard execCmd("wl-copy" & ' ' & output.strip())

      openDefaultBrowser("https://www.google.com/android/uncertified")
    of LauncherMagic.Die:
      running = false

  debug "launcher/child: adios"
  discard close(fd)
  quit(0)

proc runLauncher*(input: Input) =
  stderr.writeLine "Debug: launcher.nim - runLauncher() called."
  let pair = initIpcFds()
  let pid = fork()
  let env = getXdgEnv(input)

  # If we're the parent - we launch the GUI.
  # Else, we'll sit around waiting for commands to act upon.
  if pid != 0:
    stderr.writeLine "Debug: launcher.nim - runLauncher() - Parent process (PID: " & $getpid() & ") starting GUI."
    adw.brew(gui(Launcher(sock = pair.master, env = env)))

    # Tell the child to die.
    pair.master.send(LauncherMagic.Die)
  else:
    stderr.writeLine "Debug: launcher.nim - runLauncher() - Child process (PID: " & $getpid() & ") starting waitForCommands."
    waitForCommands(env, pair.slave)
