---------------------------------------------------------------------------
-- VTX Administrator Widget - Shared Top Bar UI                          --
-- Used by all screen-specific UI files for the top bar layout.          --
---------------------------------------------------------------------------

local ctx = ...
local Protocol = ctx.Protocol
local VTX = ctx.VTX

local TopBarUI = {}

local function getStatusLine()
  if not Protocol.isActive() then
    return "--"
  end
  if VTX.state.band == 0 then
    return "--"
  end
  return table.concat({ VTX.state.bandLetter, VTX.state.channel })
end

--- Top bar: ultra-compact single line, no background.
function TopBarUI.build(w, h)
  lvgl.build({
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      align = CENTER + VCENTER,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_TINY,
      children = {
        {
          type = lvgl.LABEL,
          align = CENTER,
          font = MIDSIZE,
          color = COLOR_THEME_PRIMARY2,
          text = function()
            local s = getStatusLine()
            if s == "--" then
              return s
            end
            local pwr = VTX.state.power > 0 and table.concat({ "P", VTX.state.power }) or "P-"
            return table.concat({ s, pwr }, " ")
          end,
        },
      },
    },
  })
end

return TopBarUI
