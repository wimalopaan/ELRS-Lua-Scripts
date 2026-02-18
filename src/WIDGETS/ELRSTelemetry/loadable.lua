---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Core Logic                                   --
-- Loaded via loadScript() from ELRSTelemetry/main.lua                  --
--                                                                      --
-- Displays ELRS link telemetry using LVGL. Uses the shared CRSF        --
-- singleton passed from main.lua for device info discovery.             --
--                                                                      --
-- UI is loaded from a screen-specific file in ui/ based on LCD_W/LCD_H.--
---------------------------------------------------------------------------

local zone, options, crsf = ...

-- Forward declarations for modules
local Telemetry

-- ============================================================================
-- Telemetry Module: cell counting, state, power mapping
-- ============================================================================

Telemetry = {
  -- Smoothed range percentage
  smoothRng = nil,

  -- Cell count detection state
  cellCnt = nil,
  cellCntCnt = 0,
  cellLastV = nil,

  -- Diversity detection
  isDiversity = false,

  -- Cached GPS position (persists across disconnects)
  gps = nil,

  -- Power level mapping table
  POWERS = { 10, 25, 50, 100, 250, 500, 1000, 2000 },
}

--- Map a power value in mW to a 0-based index.
function Telemetry.pwrToIdx(powval)
  for k, v in ipairs(Telemetry.POWERS) do
    if powval == v then
      return k - 1
    end
  end
  return 7
end

--- Cell count detection heuristic (same logic as original).
function Telemetry.checkCellCount(v)
  if (Telemetry.cellCntCnt or 0) > 5 then
    return
  end

  local cellCnt = math.floor(v / 4.35) + 1
  if (v / cellCnt) < 3.0 then
    return
  end

  if Telemetry.cellCnt ~= cellCnt then
    Telemetry.cellCnt = cellCnt
    Telemetry.cellCntCnt = 0
  else
    if Telemetry.cellLastV == v then
      return
    end
    Telemetry.cellLastV = v
    Telemetry.cellCntCnt = Telemetry.cellCntCnt + 1
  end
end

--- Read all link telemetry values into a table.
function Telemetry.readLink()
  return {
    tpwr = crsf.getSensorValue("TPWR"),
    rfmd = crsf.getSensorValue("RFMD"),
    rssi1 = crsf.getSensorValue("1RSS"),
    rssi2 = crsf.getSensorValue("2RSS"),
    rqly = crsf.getSensorValue("RQly"),
    ant = crsf.getSensorValue("ANT"),
  }
end

--- Check if a CRSF/ELRS module is available.
function Telemetry.hasModule()
  return crsf.hasCrsfModule()
end

--- Short status text when not operational or warning active.
--- Returns nil when connected with no warnings.
--- Used by both full-screen and minimized UIs.
function Telemetry.statusText()
  if not crsf.hasCrsfModule() then
    return "No CRSF module"
  end
  if not crsf.rxConnected then
    return "No RX"
  end
  if crsf.modelMismatch then
    return "Model Mismatch"
  end
  return nil
end

--- Compute smoothed range percentage from RSSI.
function Telemetry.getRangePct(tlm)
  local mod = crsf.deviceInfo
  local rssi = (tlm.ant == 1) and tlm.rssi2 or tlm.rssi1
  if rssi == nil then
    return 0
  end
  local minrssi = (mod.RFRSSI and mod.RFRSSI[(tlm.rfmd or 0) + 1]) or -128
  if rssi > -50 then
    rssi = -50
  end
  local pct = math.floor(100 * (rssi + 50) / (minrssi + 50) + 0.5)
  local smooth = Telemetry.smoothRng or pct
  if pct > smooth then
    pct = smooth + ((pct > smooth + 8) and 4 or 1)
  elseif pct < smooth then
    pct = smooth - ((pct < smooth - 8) and 4 or 1)
  end
  Telemetry.smoothRng = pct
  return pct
end

--- Get RF mode string from device info.
function Telemetry.getRfModeStr(rfmd)
  local mod = crsf.deviceInfo
  return (mod.RFMOD and mod.RFMOD[(rfmd or 0) + 1]) or table.concat({ "RFMD", tostring(rfmd or 0) })
end

--- Update GPS cache from telemetry.
function Telemetry.updateGps()
  local gps = crsf.getSensorValue("GPS")
  if gps and gps ~= 0 then
    Telemetry.gps = gps
  end
end

--- Update diversity flag from ant value.
function Telemetry.updateDiversity(ant)
  if ant and ant ~= 0 then
    Telemetry.isDiversity = true
  end
end

--- Pick the active antenna's RSSI value from a readLink() result.
function Telemetry.getRssi(tlm)
  if not tlm then
    return nil
  end
  return (tlm.ant == 1) and tlm.rssi2 or tlm.rssi1
end

--- Map range percentage to a warning color.
function Telemetry.rangeColor(pct)
  if pct > 90 then
    return RED
  end
  if pct > 70 then
    return ORANGE
  end
  return COLOR_THEME_SECONDARY1
end

--- Range percentage + RSSI text (e.g. "Range 69% -90dBm").
function Telemetry.signalText()
  if not crsf.rxConnected then
    return ""
  end
  local tlm = Telemetry.readLink()
  local pct = Telemetry.getRangePct(tlm)
  local parts = { table.concat({ "Range ", tostring(pct), "%" }) }
  local rssi = Telemetry.getRssi(tlm)
  if rssi then
    parts[#parts + 1] = table.concat({ tostring(rssi), "dBm" })
  end
  return table.concat(parts, " ")
end

--- RF mode + TX power text (e.g. "250Hz 50mW").
function Telemetry.rfDetailText()
  local tlm = Telemetry.readLink()
  local mode = Telemetry.getRfModeStr(tlm.rfmd)
  local parts = { mode }
  if crsf.rxConnected and tlm.tpwr then
    parts[#parts + 1] = table.concat({ tostring(tlm.tpwr), "mW" })
  end
  return table.concat(parts, " ")
end

-- ============================================================================
-- WidgetLayout: minimized zone container builders
-- ============================================================================

local WidgetLayout = {}

function WidgetLayout.column(w, h, opa, children)
  lvgl.build({
    {
      type = lvgl.RECTANGLE,
      x = 0,
      y = 0,
      w = w,
      h = h,
      color = COLOR_THEME_PRIMARY2,
      opacity = opa,
      filled = true,
    },
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      align = LEFT,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = 0,
      borderPad = lvgl.PAD_SMALL,
      children = children,
    },
  })
end

function WidgetLayout.row(w, h, opa, children)
  lvgl.build({
    {
      type = lvgl.RECTANGLE,
      x = 0,
      y = 0,
      w = w,
      h = h,
      color = COLOR_THEME_PRIMARY2,
      opacity = opa,
      filled = true,
    },
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      align = LEFT + VCENTER,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_TINY,
      borderPad = lvgl.PAD_SMALL,
      children = children,
    },
  })
end

-- ============================================================================
-- Screen detection and UI loading
-- ============================================================================

--- Detect screen resolution and return an ID for the per-screen UI file.
local function getScreenId()
  local w, h = LCD_W, LCD_H
  if w >= 800 then
    return "hd" -- 800x480
  elseif w < h then
    return "portrait" -- 320x480 (EL18)
  elseif w <= 320 then
    return "small" -- 320x240
  elseif h >= 320 then
    return "sd_tall" -- 480x320 (TX16S)
  else
    return "sd" -- 480x272
  end
end

--- Convert Transparency option (0-5) to LVGL opacity (255-0).
local function bgOpacity(opts)
  local t = (opts and opts.Transparency) or 2
  return math.max(0, 255 - 51 * t)
end

local screenId = getScreenId()
local uiPath = table.concat({ "/WIDGETS/ELRSTelemetry/ui/", screenId, ".lua" })
local WidgetUI = loadScript(uiPath)({
  crsf = crsf,
  Telemetry = Telemetry,
  bgOpacity = bgOpacity,
  WidgetLayout = WidgetLayout,
})

-- ============================================================================
-- Full-screen row helpers (shared across all screen sizes)
-- ============================================================================

-- Portrait screens get a narrower label column to leave more room for values.
local LABEL_PCT = (LCD_W < LCD_H) and 42 or 50

local function createDisplayRow(container, label, valueFn, colorFn)
  container:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    thickness = 0,
    flexFlow = lvgl.FLOW_ROW,
    flexPad = 0,
    children = {
      {
        type = lvgl.LABEL,
        text = label,
        color = COLOR_THEME_PRIMARY1,
        w = lvgl.PERCENT_SIZE + LABEL_PCT,
        y = lvgl.PAD_SMALL,
      },
      {
        type = lvgl.LABEL,
        text = valueFn,
        color = colorFn or COLOR_THEME_SECONDARY1,
        w = lvgl.PERCENT_SIZE + (100 - LABEL_PCT),
        y = lvgl.PAD_SMALL,
      },
    },
  })
end

local function createSectionHeader(container, title)
  container:build({
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_SMALL,
      thickness = 0,
    },
    {
      type = lvgl.LABEL,
      font = BOLD,
      color = COLOR_THEME_PRIMARY1,
      text = title,
    },
  })
end

-- ============================================================================
-- Full-screen LVGL layout (shared across all screen sizes)
-- ============================================================================

local function buildFullScreen()
  lvgl.clear()

  local pg = lvgl.page({
    title = "ExpressLRS",
    subtitle = function()
      if not Telemetry.hasModule() then
        return "No CRSF module"
      end
      if not crsf.rxConnected then
        return "No RX Connected"
      end
      if crsf.modelMismatch then
        return "Model Mismatch"
      end
      return "Telemetry"
    end,
    back = function()
      lvgl.exitFullScreen()
    end,
  })

  -- No module — show checklist instead of telemetry (matches expresslrs.lua NoModuleDialog)
  if not Telemetry.hasModule() then
    pg:rectangle({
      w = lvgl.PERCENT_SIZE + 100,
      thickness = 0,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_MEDIUM,
      children = {
        { type = lvgl.LABEL, text = "No module found. Check Model Setup:", color = COLOR_THEME_PRIMARY1 },
        { type = lvgl.LABEL, text = "- Internal/External module enabled", color = COLOR_THEME_DISABLED },
        { type = lvgl.LABEL, text = "- Protocol set to CRSF", color = COLOR_THEME_DISABLED },
        {
          type = lvgl.LABEL,
          text = "- Baud rate: 400k (250Hz), 921k (500Hz), 1.87M (F1000)",
          color = COLOR_THEME_DISABLED,
        },
      },
    })
    return
  end

  local fields = pg:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    thickness = 0,
    flexFlow = lvgl.FLOW_COLUMN,
  })

  -- Model mismatch warning banner
  fields:build({
    {
      type = lvgl.LABEL,
      font = BOLD,
      color = RED,
      text = "Model Mismatch — RC commands not sent",
      visible = function()
        return crsf.modelMismatch
      end,
    },
  })

  -- Link Status section
  createSectionHeader(fields, "Link Status")

  createDisplayRow(fields, "RF Mode", function()
    local tlm = Telemetry.readLink()
    return Telemetry.getRfModeStr(tlm.rfmd)
  end)

  createDisplayRow(fields, "Link Quality", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    return table.concat({ tostring(tlm.rqly or 0), "%" })
  end)

  createDisplayRow(fields, "RSSI 1", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    if tlm.rssi1 == nil then
      return "--"
    end
    return table.concat({ tostring(tlm.rssi1), " dBm" })
  end)

  createDisplayRow(fields, "RSSI 2", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    if tlm.rssi2 == nil then
      return "--"
    end
    return table.concat({ tostring(tlm.rssi2), " dBm" })
  end, function()
    if not Telemetry.isDiversity then
      return COLOR_THEME_DISABLED
    end
    return COLOR_THEME_SECONDARY1
  end)

  createDisplayRow(fields, "Active Antenna", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    if not Telemetry.isDiversity then
      return "N/A"
    end
    return (tlm.ant == 1) and "2" or "1"
  end)

  createDisplayRow(fields, "Range", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    local pct = Telemetry.getRangePct(tlm)
    return table.concat({ tostring(pct), "%" })
  end)

  -- Power section
  createSectionHeader(fields, "Power")

  createDisplayRow(fields, "TX Power", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    if tlm.tpwr == nil then
      return "--"
    end
    return table.concat({ tostring(tlm.tpwr), " mW" })
  end)

  createDisplayRow(fields, "Power Index", function()
    if not crsf.rxConnected then
      return "--"
    end
    local tlm = Telemetry.readLink()
    if tlm.tpwr == nil then
      return "--"
    end
    return tostring(Telemetry.pwrToIdx(tlm.tpwr))
  end)

  -- Flight Controller section
  createSectionHeader(fields, "Flight Controller")

  createDisplayRow(fields, "Battery", function()
    local vbat = crsf.getSensorValue("RxBt")
    if vbat == nil or vbat <= 0 then
      return "--"
    end
    Telemetry.checkCellCount(vbat)
    local cells = Telemetry.cellCnt
    if cells then
      return string.format("%dS %.2fV (%.2fV)", cells, vbat / cells, vbat)
    end
    return string.format("%.2fV", vbat)
  end)

  createDisplayRow(fields, "Current", function()
    local curr = crsf.getSensorValue("Curr")
    if curr == nil or curr <= 0 then
      return "--"
    end
    return string.format("%.2f A", curr)
  end)

  createDisplayRow(fields, "Flight Mode", function()
    local fm = crsf.getSensorValue("FM")
    if fm == nil or fm == 0 then
      return "--"
    end
    return tostring(fm)
  end)

  -- GPS section
  createSectionHeader(fields, "GPS")

  createDisplayRow(fields, "Satellites", function()
    local sats = crsf.getSensorValue("Sats")
    if sats == nil then
      return "--"
    end
    return tostring(sats)
  end)

  createDisplayRow(fields, "Speed", function()
    local gspd = crsf.getSensorValue("GSpd")
    if gspd == nil then
      return "--"
    end
    return string.format("%.1f", gspd)
  end)

  createDisplayRow(fields, "Altitude", function()
    local alt = crsf.getSensorValue("Alt")
    if alt == nil then
      return "--"
    end
    return tostring(alt)
  end)

  createDisplayRow(fields, "Latitude", function()
    if Telemetry.gps == nil then
      return "--"
    end
    return tostring(Telemetry.gps.lat)
  end)

  createDisplayRow(fields, "Longitude", function()
    if Telemetry.gps == nil then
      return "--"
    end
    return tostring(Telemetry.gps.lon)
  end)
end

-- ============================================================================
-- Widget lifecycle
-- ============================================================================

local wgt = {
  zone = zone,
  options = options,
}

function wgt.background()
  crsf:poll()
  crsf:requestDeviceInfo()
  crsf:requestElrsStatus()
  Telemetry.updateGps()
end

function wgt.refresh(_event, _touchState)
  wgt.background()

  -- Update diversity detection each tick
  if crsf.rxConnected then
    local tlm = Telemetry.readLink()
    Telemetry.updateDiversity(tlm.ant)
  end
end

function wgt.update(newOptions)
  wgt.options = newOptions
  if lvgl.isFullScreen() then
    buildFullScreen()
  else
    WidgetUI.build(wgt.zone, wgt.options)
  end
end

-- Initial build
WidgetUI.build(wgt.zone, wgt.options)

return wgt
