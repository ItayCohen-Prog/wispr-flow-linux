-- Hyprland 0.56 (Lua config) rules for the Wispr Flow capsule. The glass
-- draws its own frost from a snapshot of the desktop, so it needs no
-- compositor blur. The layer animates itself; skip Hyprland's fade.
hl.layer_rule({
  name = "wispr-flowbar",
  match = { namespace = "^wispr-flowbar$" },
  no_anim = true,
  blur = false,
})
