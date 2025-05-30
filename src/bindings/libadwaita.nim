## Extra bindings for new libadwaita stuff
import pkg/owlkettle
import pkg/owlkettle/bindings/gtk

{.push importc, cdecl.}
proc adw_spinner_new*(): GtkWidget
{.pop.}

renderable AdwSpinner:
  hooks:
    beforeBuild:
      # state.internalWidget = adw_spinner_new() # adw_spinner_new not found in libadwaita 1.5.0
      discard "adw_spinner_new temporarily commented out"

export AdwSpinner
