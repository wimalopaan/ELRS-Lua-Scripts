---------------------------------------------------------------------------
-- ELRS Telemetry Widget - UI for 320x240 (Small)                       --
-- Small color LCD (PA01)                                               --
---------------------------------------------------------------------------

local ctx = ...
local Telemetry = ctx.Telemetry
local crsf = ctx.crsf
local bgOpacity = ctx.bgOpacity
local WidgetLayout = ctx.WidgetLayout

local WidgetUI = {}

-- Breakpoints: absolute pixel values for 320x240.
-- Smallest color screen — everything is compact.
WidgetUI.breakpoints = {
  topBarW = 80,
  sixthH = 30,
  quarterH = 42,
  thirdH = 58,
}

WidgetUI.fonts = {
  sixth = { hero = BOLD },
  quarter = { hero = BOLD },
  third = { hero = BOLD, detail = SMLSIZE },
  full = { hero = MIDSIZE, detail = SMLSIZE },
}

-- ============================================================================
-- Minimized display helpers
-- ============================================================================

local function heroColorMismatch()
  if crsf.modelMismatch then
    return RED
  end
  return COLOR_THEME_PRIMARY1
end

local function detailColor()
  if not crsf.rxConnected then
    return COLOR_THEME_SECONDARY1
  end
  return Telemetry.rangeColor(Telemetry.smoothRng or 0)
end

local function heroTextLq()
  local status = Telemetry.statusText()
  if status then
    return status
  end
  local tlm = Telemetry.readLink()
  return table.concat({ "LQ ", tostring(tlm.rqly or 0), "%" })
end

-- ============================================================================
-- Minimized layout builders (by widget height tier)
-- ============================================================================

local TopBarUI = loadScript("/WIDGETS/ELRSTelemetry/ui/topbar.lua")({
  crsf = crsf,
  Telemetry = Telemetry,
})

--- 1/6: single compact line — LQ (bold) + Range/dBm (colored) + RF mode (neutral).
--- Fixed-width columns prevent layout jumping when digit counts change.
function WidgetUI.buildSixth(w, h, opa)
  local c1w = math.floor(w * 0.28)
  local c2w = math.floor(w * 0.40)
  local c3w = w - c1w - c2w
  local columns = {
    {
      type = lvgl.BOX,
      w = c1w,
      h = lvgl.UI_ELEMENT_HEIGHT,
      children = {
        {
          type = lvgl.LABEL,
          y = lvgl.PAD_SMALL,
          font = BOLD,
          color = heroColorMismatch,
          text = heroTextLq,
        },
      },
    },
    {
      type = lvgl.BOX,
      w = c2w,
      h = lvgl.UI_ELEMENT_HEIGHT,
      children = {
        {
          type = lvgl.LABEL,
          y = lvgl.PAD_SMALL,
          font = SMLSIZE,
          color = detailColor,
          text = Telemetry.signalText,
        },
      },
    },
    {
      type = lvgl.BOX,
      w = c3w,
      h = lvgl.UI_ELEMENT_HEIGHT,
      children = {
        {
          type = lvgl.LABEL,
          y = lvgl.PAD_SMALL,
          font = SMLSIZE,
          color = COLOR_THEME_SECONDARY1,
          text = function()
            local tlm = Telemetry.readLink()
            return Telemetry.getRfModeStr(tlm.rfmd)
          end,
        },
      },
    },
  }
  WidgetLayout.row(w, h, opa, columns)
end

--- 1/4: LQ + Range/dBm on row 1, RF mode + Power on row 2.
--- Fixed-width first column prevents layout jumping when digit counts change.
function WidgetUI.buildQuarter(w, h, opa)
  local c1w = math.floor(w * 0.30)
  local rows = {
    {
      type = lvgl.BOX,
      w = w,
      align = LEFT + VCENTER,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_TINY,
      children = {
        {
          type = lvgl.LABEL,
          w = c1w,
          align = LEFT,
          font = BOLD,
          color = heroColorMismatch,
          text = heroTextLq,
        },
        {
          type = lvgl.LABEL,
          align = LEFT,
          font = SMLSIZE,
          color = detailColor,
          text = Telemetry.signalText,
        },
      },
    },
    {
      type = lvgl.BOX,
      w = w,
      align = LEFT,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_TINY,
      children = {
        {
          type = lvgl.LABEL,
          align = LEFT,
          font = SMLSIZE,
          color = COLOR_THEME_SECONDARY1,
          text = Telemetry.rfDetailText,
        },
      },
    },
  }
  WidgetLayout.column(w, h, opa, rows)
end

--- 1/3: hero LQ + Range/RSSI detail + RF mode. No title on small screen.
function WidgetUI.buildThird(w, h, opa)
  local rows = {}
  -- No title row — too tight on 320x240
  rows[#rows + 1] = {
    type = lvgl.LABEL,
    align = LEFT,
    font = WidgetUI.fonts.third.hero,
    color = heroColorMismatch,
    text = heroTextLq,
  }
  rows[#rows + 1] = {
    type = lvgl.LABEL,
    align = LEFT,
    font = WidgetUI.fonts.third.detail,
    color = detailColor,
    text = Telemetry.signalText,
  }
  rows[#rows + 1] = {
    type = lvgl.LABEL,
    align = LEFT,
    font = SMLSIZE,
    color = COLOR_THEME_SECONDARY1,
    text = Telemetry.rfDetailText,
  }

  WidgetLayout.column(w, h, opa, rows)
end

--- 1/1: full telemetry display with title.
function WidgetUI.buildFull(w, h, opa)
  local rows = {
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = BOLD,
      color = COLOR_THEME_SECONDARY1,
      text = "ExpressLRS",
    },
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = function()
        return BOLD
      end,
      color = heroColorMismatch,
      text = heroTextLq,
    },
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = WidgetUI.fonts.full.detail,
      color = detailColor,
      text = Telemetry.signalText,
    },
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = Telemetry.rfDetailText,
    },
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = SMLSIZE,
      color = COLOR_THEME_PRIMARY3,
      text = function()
        local vbat = crsf.getSensorValue("RxBt")
        if vbat == nil or vbat <= 0 then
          return ""
        end
        Telemetry.checkCellCount(vbat)
        local cells = Telemetry.cellCnt
        if cells then
          return string.format("Bat %dS %.2fV", cells, vbat / cells)
        end
        return string.format("Bat %.2fV", vbat)
      end,
    },
  }
  WidgetLayout.column(w, h, opa, rows)
end

--- Route to the appropriate minimized layout based on widget dimensions.
function WidgetUI.build(wgtZone, opts)
  lvgl.clear()
  local w, h = wgtZone.w, wgtZone.h
  local opa = bgOpacity(opts)
  local bp = WidgetUI.breakpoints
  if w < bp.topBarW then
    TopBarUI.build(w, h)
  elseif h < bp.sixthH then
    WidgetUI.buildSixth(w, h, opa)
  elseif h < bp.quarterH then
    WidgetUI.buildQuarter(w, h, opa)
  elseif h < bp.thirdH then
    WidgetUI.buildThird(w, h, opa)
  else
    WidgetUI.buildFull(w, h, opa)
  end
end

return WidgetUI
