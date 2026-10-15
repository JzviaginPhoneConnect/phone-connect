# Layout of the macOS installer window (.dmg), for dmgbuild
# (https://dmgbuild.readthedocs.io). Called by build/build-macos.sh:
#   dmgbuild -s build/dmg-settings.py -D app=<PhoneConnect.app> -D background=<.png/.tiff>
#            -D icon=<PhoneConnect.icns> "PhoneConnect" <output.dmg>
# Icon positions must match assets/make_dmg_background.py.
import os.path

app = defines["app"]                      # noqa: F821  (provided by dmgbuild)
background = defines["background"]        # noqa: F821
icon = defines["icon"]                    # noqa: F821  (the volume's own icon)
app_name = os.path.basename(app)

format = "UDZO"                           # compressed, read-only
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

icon_locations = {
    app_name: (160, 200),
    "Applications": (440, 200),
}

window_rect = ((200, 120), (600, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
arrange_by = None
