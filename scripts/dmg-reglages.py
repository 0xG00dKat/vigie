# Réglages de dmgbuild pour l'image disque de Vigie (lus par scripts/make-dmg.sh).
# Fenêtre de 660 × 400 sur fond noir (Support/dmg-fond.tiff, dessiné par scripts/dmg-fond.html) :
# Vigie à gauche, le raccourci Applications à droite, une flèche entre les deux.
import os

app = defines["app"]  # chemin de Vigie.app, passé par make-dmg.sh (-D app=…)
racine = os.path.dirname(os.path.dirname(os.path.abspath(app)))

format = "UDZO"
filesystem = "HFS+"
size = None
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = ["Vigie.app"]

background = os.path.join(racine, "Support", "dmg-fond.tiff")
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 12
arrange_by = None
icon_locations = {"Vigie.app": (180, 180), "Applications": (480, 180)}
