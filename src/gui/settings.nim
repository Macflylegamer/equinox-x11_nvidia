## GUI shell
import std/[logging, options, posix, strutils]
import pkg/[owlkettle, shakar], pkg/owlkettle/adw
import ../container/app_config, ./common

type SettingsState* {.pure.} = enum
  General
  Renderer

viewable SettingsMenu:
  collapsed:
    bool = true
  config:
    ptr ConfigData

  state:
    SettingsState
  selected:
    int

proc setState(app: SettingsMenuState, state: SettingsState) =
  if app.state == state:
    return

  debug "settings: state=" & $state
  app.collapsed = true
  app.state = state

method view(app: SettingsMenuState): Widget =
  result = gui:
    Window:
      title = "Equinox Settings"
      defaultSize = (600, 400)

      AdwHeaderBar {.addTitlebar.}:
        showTitle = true
        style = HeaderBarFlat

        Button {.addLeft.}:
          icon = "sidebar-show-symbolic"
          style = [ButtonFlat]

          proc clicked() =
            app.collapsed = not app.collapsed
            debug "settings: collapsed: " & $app.collapsed

        # Unless we add more options in here I'm commenting it out
        # Also added a save and quit if you ever want to use it
        #[ MenuButton {.addRight.}:
          icon = "open-menu-symbolic"
          style = [ButtonFlat]

          PopoverMenu:
            sensitive = true
            sizeRequest = (-1, -1)
            position = PopoverBottom

            Box {.name: "main".}:
              orient = OrientY
              margin = 4
              spacing = 3

              ModelButton:
                text = "About Equinox"

                proc clicked() =
                  openAboutMenu(app)

              Separator()

              ModelButton:
                text = "Save and Quit"

                proc clicked() =
                  info "equinox: saving configuration changes"
                  app.config[].save()
                  info "equinox: closing settings app..."
                  quit()]#

        Button {.addRight.}:
          icon = "help-about-symbolic"
          tooltip = "Open the About Window"
          style = [ButtonFlat]

          proc clicked() =
            openAboutMenu(app)

        Button {.addRight.}:
          icon = "media-floppy-symbolic"
          tooltip = "Save changes"
          style = [ButtonFlat]

          proc clicked() =
            info "equinox: saving configuration changes"
            app.config[].save()

      OverlaySplitView:
        collapsed = not app.collapsed
        enableHideGesture = true
        enableShowGesture = true
        showSidebar = not app.collapsed
        sensitive = true
        sizeRequest = (-1, -1)
        minSidebarWidth = 350f

        Box {.addSidebar.}:
          orient = OrientY
          spacing = 8
          margin = 8
          Button {.expand: false.}:
            ButtonContent:
              label = "General Settings"
              iconName = "user-home-symbolic"
              style = [ButtonFlat]
              useUnderline = false

            proc clicked() =
              app.setState(SettingsState.General)

          Button {.expand: false.}:
            ButtonContent:
              label = "Renderer Settings"
              iconName = "video-display-symbolic"
              style = [ButtonFlat]
              useUnderline = false

            proc clicked() =
              app.setState(SettingsState.Renderer)

        case app.state
        of SettingsState.General:
          Clamp:
            maximumSize = 500
            margin = 12
            Box:
              orient = OrientY
              spacing = 12

              PreferencesGroup {.expand: false.}:
                title = "General Settings"
                description = "These settings dictate Equinox's behaviour."

                ActionRow:
                  title = "Show Discord RPC"
                  subtitle =
                    "When enabled, Equinox will display the current experience you're playing on Discord."
                  tooltip = "This is enabled by default"

                  Switch() {.addSuffix.}:
                    state = app.config.discordRpc

                    proc changed(state: bool) =
                      app.config.discordRpc = state

        of SettingsState.Renderer:
          Clamp:
            maximumSize = 500
            margin = 12
            Box:
              orient = OrientY
              spacing = 12

              PreferencesGroup {.expand: false.}:
                title = "Rendering Parameters"
                description =
                  "These settings control how rendering is handled by Equinox."

                ComboRow:
                  title = "Rendering Backend"
                  subtitle = "Only modify if your GPU doesn't support Vulkan"
                  tooltip = "Default is Vulkan"

                  items = @["Vulkan", "OpenGL"]
                  selected = app.selected

                  proc select(index: int) =
                    app.selected = index

                    case index
                    of 0:
                      app.config.renderer = "vulkan"
                    of 1:
                      app.config.renderer = "opengl"
                    else:
                      # This case should ideally not be reached if ComboRow items are fixed.
                      discard

                ActionRow:
                  title = "Maximum FPS"
                  subtitle = "If you have VSync enabled, this will be ignored."
                  tooltip = "Default is 60"

                  Entry {.addSuffix.}:
                    text = (
                      if *app.config.maxFps:
                        $(&app.config.maxFps)
                      else:
                        "60"
                    )

                    proc changed(text: string) =
                      try:
                        app.config.maxFps = some(parseUint(text).uint16)
                      except ValueError:
                        discard

              PreferencesGroup {.expand: true.}:
                title = "Advanced Parameters"
                description =
                  "<b>Do not modify these settings if you aren't aware of what they do</b>."

                ActionRow:
                  title = "GPU Memory Allocator"
                  subtitle =
                    "This decides which VRAM allocator the Android runtime will use."
                  tooltip = "Default is minigbm_gbm_mesa"

                  Entry {.addSuffix.}:
                    text = app.config.allocator

                    proc changed(text: string) =
                      app.config.allocator = text

        else:
          discard

proc runSettingsMenu*() =
  var config = loadAppConfig($getpwuid(getuid()).pwName)
  adw.brew(
    gui(
      SettingsMenu(
        config = config.addr,
        collapsed = true,
        selected =
          (
            case config.renderer.toRenderingBackend() # FIXME: terrible, ugly and awful hack that'll break if you reorder shit in the menu :^)
            of RenderingBackend.Vulkan: 0
            of RenderingBackend.OpenGL: 1
          )
      )
    )
  )

  info "equinox: saving configuration changes"
  config.save()
  info "equinox: done!"
