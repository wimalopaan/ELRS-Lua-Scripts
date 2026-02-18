---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Shared Top Bar UI                             --
-- Used by all screen-specific UI files for the top bar layout.          --
---------------------------------------------------------------------------

local ctx = ...
local crsf = ctx.crsf
local Telemetry = ctx.Telemetry

local TopBarUI = {}

local function getRssi(tlm)
  if not tlm then
    return nil
  end
  return (tlm.ant == 1) and tlm.rssi2 or tlm.rssi1
end

--- Top bar: two lines stacked, no background.
function TopBarUI.build(w, h)
  lvgl.build({
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      align = CENTER,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = 0,
      children = {
        {
          type = lvgl.LABEL,
          align = CENTER,
          font = SMLSIZE,
          color = function()
            if crsf.modelMismatch then
              return RED
            end
            return COLOR_THEME_PRIMARY2
          end,
          text = function()
            if crsf.modelMismatch then
              return "Model"
            end
            if not crsf.rxConnected then
              return "--"
            end
            local tlm = Telemetry.readLink()
            return table.concat({ "LQ ", tostring(tlm.rqly or 0), "%" })
          end,
        },
        {
          type = lvgl.LABEL,
          align = CENTER,
          font = SMLSIZE,
          color = function()
            if crsf.modelMismatch then
              return RED
            end
            return COLOR_THEME_PRIMARY2
          end,
          text = function()
            if crsf.modelMismatch then
              return "Mismatch"
            end
            if not crsf.rxConnected then
              return "--"
            end
            local tlm = Telemetry.readLink()
            local rssi = getRssi(tlm)
            if rssi == nil then
              return ""
            end
            return table.concat({ tostring(rssi), "dBm" })
          end,
        },
      },
    },
  })
end

return TopBarUI
