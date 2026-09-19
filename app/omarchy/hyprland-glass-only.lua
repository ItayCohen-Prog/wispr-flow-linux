-- Optional preset for an Omarchy desktop that currently has blur disabled.
-- Keep existing windows/layers unblurred, and frost only the Wispr capsule.
-- Load after your other rules. Remove this preset to allow other blur rules.
hl.config({ decoration = { blur = {
  enabled = true,
  size = 6,
  passes = 2,
  new_optimizations = true,
  xray = false,
} } })
hl.window_rule({ name = "wispr-preserve-unblurred-windows", match = { class = ".*" }, no_blur = true })
hl.layer_rule({ name = "wispr-preserve-unblurred-layers", match = { namespace = ".*" }, blur = false, blur_popups = false, xray = false })
hl.layer_rule({
  name = "wispr-capsule-glass",
  match = { namespace = "^wispr-flowbar$" },
  blur = true,
  -- The material shadow is at most 0.18 alpha. Do not blur its rectangle.
  ignore_alpha = 0.2,
  xray = false,
  no_anim = true,
})
