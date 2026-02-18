---- #########################################################################
---- # BW LCD UI: Rendering, input handling, cursor management            #
---- # For black & white radios (no LVGL required)                        #
---- #########################################################################

local deps = ...

local App = deps.App
local Navigation = deps.Navigation
local Protocol = deps.Protocol
local VERSION = deps.VERSION

-- ============================================================================
-- UI state
-- ============================================================================

local UI = {
  -- Cursor/selection state (owned entirely by this module)
  lineIndex = 1,
  pageOffset = 0,
  edit = nil,

  -- Visible field list (rebuilt on invalidate)
  visibleFields = nil,

  -- Layout constants (set in UI.init)
  COL1 = 0,
  COL2 = 70,
  maxLineIndex = 6,
  textSize = 8,
  textYoffset = 3,

  -- Redraw state
  forceRedraw = true,
  folderWasReady = false,

  -- Warning flashing
  titleShowWarn = nil,
  titleShowWarnTimeout = 100,

  -- Command popup spinner
  commandRunningIndicator = 1,
}

-- ============================================================================
-- Interface: init
-- ============================================================================

function UI.init()
  if LCD_W == 212 then
    UI.COL2 = 110
  else
    UI.COL2 = 70
  end
  if LCD_H == 96 then
    UI.maxLineIndex = 9
  else
    UI.maxLineIndex = 6
  end
  UI.COL1 = 0
  UI.textYoffset = 3
  UI.textSize = 8
end

-- ============================================================================
-- Interface: invalidate (does NOT reset cursor)
-- ============================================================================

function UI.invalidate()
  UI.forceRedraw = true
  UI.visibleFields = nil
end

-- ============================================================================
-- Interface: onDeviceLoaded (resets cursor + invalidates)
-- ============================================================================

function UI.onDeviceLoaded()
  UI.lineIndex = 1
  UI.pageOffset = 0
  UI.invalidate()
end

-- ============================================================================
-- Interface: onNewDevice
-- ============================================================================

function UI.onNewDevice()
  UI.invalidate()
end

-- ============================================================================
-- Interface: handleNoModule
-- ============================================================================

function UI.handleNoModule()
  UI.drawAlert("  No ExpressLRS", {
    " Enable a CRSF Internal",
    "   or External module in",
    "       Model settings",
    "  If module is internal",
    " also set Internal RF to",
    " CRSF in SYS->Hardware",
  })
end

-- ============================================================================
-- Interface: handleUnsupported
-- ============================================================================

function UI.handleUnsupported()
  UI.drawAlert("Unsupported Firmware", {
    "ELRS 1.x firmware detected.",
    "Please update to 3.x.",
  })
end

-- ============================================================================
-- Interface: render
-- ============================================================================

function UI.render(event, _touchState)
  -- Warning flashing timer
  local time = getTime()
  if time > UI.titleShowWarnTimeout then
    UI.titleShowWarn = (Protocol.elrsFlags > Protocol.CRSF.ELRS_FLAGS_STATUS_MASK and not UI.titleShowWarn) or nil
    UI.titleShowWarnTimeout = time + 100
    UI.forceRedraw = true
  end

  -- Force redraw during loading to show progress bar
  if #Protocol.loadQueue > 0 then
    UI.forceRedraw = true
  end

  -- Render: command popup or normal page
  if Protocol.fieldPopup ~= nil then
    UI.drawPopup(event)
  elseif event ~= 0 or UI.forceRedraw or UI.edit then
    UI.drawPage(event)
    UI.forceRedraw = false
  end
end

-- ============================================================================
-- Alert screen (clear screen + title + body messages)
-- ============================================================================

function UI.drawAlert(title, msgs)
  lcd.clear()
  local y = 0
  lcd.drawText(2, y, title, MIDSIZE)
  y = y + (UI.textSize * 2) - 2
  for _, msg in ipairs(msgs) do
    lcd.drawText(2, y, msg)
    y = y + UI.textSize
  end
end

-- ============================================================================
-- User action handlers (call App for business logic, manage own state)
-- ============================================================================

function UI.openFolder(folderId, folderName)
  App.enterFolder(folderId, folderName, { li = UI.lineIndex, po = UI.pageOffset })
  UI.lineIndex = 1
  UI.pageOffset = 0
  UI.invalidate()
end

function UI.switchDevice(deviceId)
  if App.switchDevice(deviceId, { li = UI.lineIndex, po = UI.pageOffset }) then
    UI.lineIndex = 1
    UI.pageOffset = 0
    UI.invalidate()
  end
end

function UI.handleBack()
  if Navigation.isAtRoot() then
    App.reloadAtRoot()
  else
    local entry = App.goBack()
    if entry then
      UI.lineIndex = entry.li or 1
      UI.pageOffset = entry.po or 0
      if entry.type == Navigation.TYPE_DEVICE and entry.prevDeviceId then
        local prevDevice = Protocol.getDevice(entry.prevDeviceId)
        if prevDevice then
          Protocol.setDevice(prevDevice)
        end
      end
    end
  end
  UI.invalidate()
end

-- ============================================================================
-- Build visible field list for current navigation state
-- ============================================================================

function UI.buildVisibleFields()
  local currentFolder = Navigation.getCurrent()
  local vf = {}

  if currentFolder == Navigation.FOLDER_OTHER_DEVICES then
    for _, device in ipairs(Protocol.devices) do
      if device.id ~= Protocol.deviceId then
        vf[#vf + 1] = { id = device.id, name = device.name, type = Protocol.CRSF.DEVICE }
      end
    end
  else
    local fields = Protocol.getFieldsInFolder(currentFolder)
    for _, field in ipairs(fields) do
      vf[#vf + 1] = field
    end

    if currentFolder == nil and #Protocol.devices > 1 and not Navigation.hasDeviceEntry() then
      vf[#vf + 1] = { name = "Other Devices", type = Protocol.CRSF.DEVICE_FOLDER }
    end
  end

  UI.visibleFields = vf
end

function UI.getField(line)
  if not UI.visibleFields then
    UI.buildVisibleFields()
  end
  return UI.visibleFields[line]
end

function UI.getFieldCount()
  if not UI.visibleFields then
    UI.buildVisibleFields()
  end
  return #UI.visibleFields
end

function UI.getSelectableCount()
  return UI.getFieldCount() + 1
end

function UI.isOnBackExit()
  return UI.lineIndex > UI.getFieldCount()
end

function UI.getBackExitLabel()
  if Navigation.isAtRoot() then
    return "-- EXIT (" .. VERSION .. ") --"
  else
    return "----BACK----"
  end
end

-- ============================================================================
-- Field value increment
-- ============================================================================

function UI.incrField(step)
  local field = UI.getField(UI.lineIndex)
  if not field then
    return
  end
  local min, max = 0, 0
  if field.type <= Protocol.CRSF.FLOAT then
    min = field.min or 0
    max = field.max or 0
    step = (field.step or 1) * step
  elseif field.type == Protocol.CRSF.TEXT_SELECTION then
    min = 0
    max = #field.values - 1
  end

  local newval = field.value
  repeat
    newval = newval + step
    if newval < min then
      newval = min
    elseif newval > max then
      newval = max
    end

    if field.values == nil or #field.values[newval + 1] ~= 0 then
      field.value = newval
      return
    end
  until newval == min or newval == max
end

-- ============================================================================
-- Field selection navigation
-- ============================================================================

function UI.selectField(step)
  local count = UI.getSelectableCount()
  if count == 0 then
    return
  end
  local fieldCount = UI.getFieldCount()
  local newLineIndex = UI.lineIndex
  repeat
    newLineIndex = newLineIndex + step
    if newLineIndex <= 0 then
      newLineIndex = count
    elseif newLineIndex > count then
      newLineIndex = 1
      UI.pageOffset = 0
    end
    if newLineIndex > fieldCount then
      break
    end
    local field = UI.getField(newLineIndex)
    if field and field.name then
      break
    end
  until newLineIndex == UI.lineIndex
  UI.lineIndex = newLineIndex
  if UI.lineIndex > UI.maxLineIndex + UI.pageOffset then
    UI.pageOffset = UI.lineIndex - UI.maxLineIndex
  elseif UI.lineIndex <= UI.pageOffset then
    UI.pageOffset = UI.lineIndex - 1
  end
end

-- ============================================================================
-- BW field display functions
-- ============================================================================

local function fieldIntDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, field.value .. (field.unit or ""), attr)
end

local function fieldFloatDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, string.format(field.fmt, field.value / field.prec), attr)
end

local function fieldTextSelDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, (field.values[field.value + 1] or "ERR") .. (field.unit or ""), attr)
end

local function fieldStringDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, field.value or "", attr)
end

local function fieldFolderDisplay(field, y, attr)
  lcd.drawText(UI.COL1, y, "> " .. field.name, attr + BOLD)
end

local function fieldCommandDisplay(field, y, attr)
  lcd.drawText(10, y, "[" .. field.name .. "]", attr + BOLD)
end

local displayHandlers = {}
displayHandlers[Protocol.CRSF.UINT8] = fieldIntDisplay
displayHandlers[Protocol.CRSF.INT8] = fieldIntDisplay
displayHandlers[Protocol.CRSF.UINT16] = fieldIntDisplay
displayHandlers[Protocol.CRSF.INT16] = fieldIntDisplay
displayHandlers[Protocol.CRSF.FLOAT] = fieldFloatDisplay
displayHandlers[Protocol.CRSF.TEXT_SELECTION] = fieldTextSelDisplay
displayHandlers[Protocol.CRSF.STRING] = fieldStringDisplay
displayHandlers[Protocol.CRSF.INFO] = fieldStringDisplay
displayHandlers[Protocol.CRSF.FOLDER] = fieldFolderDisplay
displayHandlers[Protocol.CRSF.COMMAND] = fieldCommandDisplay
displayHandlers[Protocol.CRSF.DEVICE] = fieldCommandDisplay
displayHandlers[Protocol.CRSF.DEVICE_FOLDER] = fieldFolderDisplay

-- ============================================================================
-- Title bar drawing
-- ============================================================================

function UI.drawTitle()
  local barHeight = 9
  local goodBadPkt = ""
  if Protocol.receivedPackets then
    local state = Protocol.isConnected() and "C" or "-"
    goodBadPkt = string.format("%u/%u   %s", Protocol.lostPackets, Protocol.receivedPackets, state)
  end

  local loaded, total = Protocol.getFolderLoadProgress(Navigation.getCurrent())
  if not UI.titleShowWarn then
    lcd.drawText(LCD_W - 1, 1, goodBadPkt, RIGHT)
    lcd.drawLine(LCD_W - 10, 0, LCD_W - 10, barHeight - 1, SOLID, INVERS)
  end

  if loaded and total and total > 0 and loaded < total then
    lcd.drawFilledRectangle(UI.COL2, 0, LCD_W, barHeight, GREY_DEFAULT)
    lcd.drawGauge(0, 0, UI.COL2, barHeight, loaded, total, 0)
  else
    lcd.drawFilledRectangle(0, 0, LCD_W, barHeight, GREY_DEFAULT)
    if UI.titleShowWarn then
      lcd.drawText(UI.COL1, 1, Protocol.elrsFlagsInfo, INVERS)
    else
      lcd.drawText(UI.COL1, 1, Protocol.deviceName or "Searching...", INVERS)
    end
  end
end

-- ============================================================================
-- Warning display
-- ============================================================================

function UI.drawWarning()
  lcd.drawText(UI.COL1, UI.textSize * 2, "Error:")
  lcd.drawText(UI.COL1, UI.textSize * 3, Protocol.elrsFlagsInfo)
  lcd.drawText(LCD_W / 2, UI.textSize * 5, "[OK]", BLINK + INVERS + CENTER)
end

-- ============================================================================
-- Event handling
-- ============================================================================

function UI.handleEvent(event)
  if UI.getSelectableCount() == 0 then
    return
  end

  if event == EVT_VIRTUAL_EXIT then
    if UI.edit then
      UI.edit = nil
      local field = UI.getField(UI.lineIndex)
      if field and field.id then
        Protocol.reloadCurField(field)
      end
    else
      UI.handleBack()
    end
  elseif event == EVT_VIRTUAL_ENTER then
    if Protocol.elrsFlags > Protocol.CRSF.ELRS_FLAGS_WARNING_THRESHOLD then
      Protocol.elrsFlags = 0
      Protocol.push(Protocol.CRSF.FRAMETYPE_PARAMETER_WRITE, { Protocol.deviceId, Protocol.handsetId, 0x2E, 0x00 })
    elseif UI.isOnBackExit() then
      if Navigation.isAtRoot() then
        App.shouldExit = true
      else
        UI.handleBack()
      end
    else
      local field = UI.getField(UI.lineIndex)
      if field and field.name then
        local ft = field.type

        if ft == Protocol.CRSF.FOLDER then
          UI.openFolder(field.id, field.name)
        elseif ft == Protocol.CRSF.DEVICE_FOLDER then
          UI.openFolder(Navigation.FOLDER_OTHER_DEVICES, "Other Devices")
        elseif ft == Protocol.CRSF.DEVICE then
          UI.switchDevice(field.id)
        elseif ft == Protocol.CRSF.COMMAND then
          Protocol.handleCommandSave(field)
        elseif not field.disabled and ft <= Protocol.CRSF.TEXT_SELECTION then
          UI.edit = not UI.edit
          if not UI.edit then
            Protocol.fieldIntSave(field)
            Protocol.reloadRelatedFields(field)
          end
        end
      end
    end
  elseif UI.edit then
    if event == EVT_VIRTUAL_NEXT then
      UI.incrField(1)
    elseif event == EVT_VIRTUAL_PREV then
      UI.incrField(-1)
    end
  else
    if event == EVT_VIRTUAL_NEXT then
      UI.selectField(1)
    elseif event == EVT_VIRTUAL_PREV then
      UI.selectField(-1)
    end
  end
end

-- ============================================================================
-- Main page rendering
-- ============================================================================

function UI.drawPage(event)
  UI.handleEvent(event)

  lcd.clear()
  UI.drawTitle()

  if Protocol.elrsFlags > Protocol.CRSF.ELRS_FLAGS_WARNING_THRESHOLD then
    UI.drawWarning()
  else
    local totalCount = UI.getSelectableCount()
    for y = 1, UI.maxLineIndex + 1 do
      local idx = UI.pageOffset + y
      if idx > totalCount then
        break
      end
      local yPos = y * UI.textSize + UI.textYoffset
      local isSelected = (UI.lineIndex == idx)
      local attr = isSelected and ((UI.edit and BLINK or 0) + INVERS) or 0

      if idx > UI.getFieldCount() then
        lcd.drawText(10, yPos, "[" .. UI.getBackExitLabel() .. "]", attr + BOLD)
      else
        local field = UI.getField(idx)
        if field and field.name then
          local ft = field.type
          if ft < Protocol.CRSF.FOLDER or ft == Protocol.CRSF.INFO then
            lcd.drawText(UI.COL1, yPos, field.name, 0)
          end
          local displayFn = displayHandlers[ft]
          if displayFn then
            displayFn(field, yPos, attr)
          end
        end
      end
    end
  end
end

-- ============================================================================
-- Command popup rendering
-- ============================================================================

function UI.drawPopup(event)
  if event == EVT_VIRTUAL_EXIT then
    Protocol.push(
      Protocol.CRSF.FRAMETYPE_PARAMETER_WRITE,
      { Protocol.deviceId, Protocol.handsetId, Protocol.fieldPopup.id, Protocol.CRSF.CMD_CANCEL }
    )
    Protocol.fieldTimeout = getTime() + 200
  end

  if
    Protocol.fieldPopup.status == Protocol.CRSF.CMD_IDLE and Protocol.fieldPopup.lastStatus ~= Protocol.CRSF.CMD_IDLE
  then
    popupConfirmation(Protocol.fieldPopup.info or "", "Stopped!", event)
    Protocol.reloadAllFields()
    Protocol.fieldPopup = nil
  elseif Protocol.fieldPopup.status == Protocol.CRSF.CMD_ASKCONFIRM then
    local result = popupConfirmation(Protocol.fieldPopup.info or "", "PRESS [OK] to confirm", event)
    Protocol.fieldPopup.lastStatus = Protocol.fieldPopup.status
    if result == "OK" then
      Protocol.commandConfirm()
    elseif result == "CANCEL" then
      Protocol.fieldPopup = nil
    end
  elseif Protocol.fieldPopup.status == Protocol.CRSF.CMD_EXECUTING then
    if Protocol.fieldChunk == 0 then
      UI.commandRunningIndicator = (UI.commandRunningIndicator % 4) + 1
    end
    local result = popupConfirmation(
      (Protocol.fieldPopup.info or "")
        .. " ["
        .. string.sub("|/-\\", UI.commandRunningIndicator, UI.commandRunningIndicator)
        .. "]",
      "Press [RTN] to exit",
      event
    )
    Protocol.fieldPopup.lastStatus = Protocol.fieldPopup.status
    if result == "CANCEL" then
      Protocol.commandCancel()
    end
  end
end

return UI
