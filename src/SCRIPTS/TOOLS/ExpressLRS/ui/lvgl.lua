---- #########################################################################
---- # LVGL UI: Color LCD rendering, dialogs, command pages               #
---- # For color LCD radios with EdgeTX 2.11.4+ LVGL support              #
---- #########################################################################

local deps = ...

local App = deps.App
local Navigation = deps.Navigation
local Protocol = deps.Protocol
local VERSION = deps.VERSION

local VERSION_CHECK_ENABLED = true

-- ============================================================================
-- UI state
-- ============================================================================

local UI = {
  currentPage = nil,
  uiBuilt = false,
  folderWasReady = false,

  -- Warning/command state (LVGL-specific)
  warningDismissed = false,
  warningDismissedAt = nil,
  warningDialog = nil,
  commandDialog = nil,
}

-- ============================================================================
-- Dialogs Module: Generic LVGL wrappers
-- ============================================================================

local Dialogs = {}

function Dialogs.showConfirm(options)
  return lvgl.confirm({
    title = options.title,
    message = options.message,
    confirm = options.onConfirm,
    cancel = options.onCancel,
  })
end

function Dialogs.showMessage(options)
  return lvgl.message({
    title = options.title,
    message = options.message,
  })
end

-- ============================================================================
-- ModelMismatchDialog
-- ============================================================================

local ModelMismatchDialog = {}

function ModelMismatchDialog.show(onContinue, onExit)
  local dg = lvgl.dialog({
    title = "Model Mismatch",
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_SMALL,
  })

  dg:build({
    {
      type = lvgl.BOX,
      x = 10,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_SMALL,
      children = {
        { type = lvgl.LABEL, text = "Receiver connected but Model ID doesn't match." },
        { type = lvgl.LABEL, text = "This prevents controlling the wrong model." },
        { type = lvgl.LABEL, text = "To use this receiver:" },
        { type = lvgl.LABEL, text = "Set Model Match to OFF" },
      },
    },
    {
      type = lvgl.BOX,
      w = lvgl.PERCENT_SIZE + 100,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_SMALL,
      children = {
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 48,
          text = "Continue",
          press = function()
            dg:close()
            onContinue()
          end,
        },
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 48,
          text = "Exit to Change Model",
          press = function()
            dg:close()
            onExit()
          end,
        },
      },
    },
  })

  return dg
end

-- ============================================================================
-- NoModuleDialog
-- ============================================================================

local NoModuleDialog = {}

function NoModuleDialog.show(onExit)
  lvgl.clear()

  local dg = lvgl.dialog({
    title = "No Module Found: Check Model Settings",
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_SMALL,
    close = onExit,
  })

  dg:build({
    {
      type = lvgl.BOX,
      x = 10,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_SMALL,
      children = {
        { type = lvgl.LABEL, text = "- Internal/External module enabled" },
        { type = lvgl.LABEL, text = "- Protocol set to CRSF" },
        { type = lvgl.LABEL, text = "- Minimum Baud rate (depends on packet rate):" },
        { type = lvgl.LABEL, font = SMLSIZE, text = "  400k for 250Hz" },
        { type = lvgl.LABEL, font = SMLSIZE, text = "  921k for 500Hz" },
        { type = lvgl.LABEL, font = SMLSIZE, text = "  1.87M for F1000" },
      },
    },
    {
      type = lvgl.BOX,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      flexFlow = lvgl.FLOW_ROW,
      children = {
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 98,
          text = "Exit",
          press = function()
            dg:close()
            onExit()
          end,
        },
      },
    },
  })

  return dg
end

-- ============================================================================
-- CommandPage: Non-modal pages for command confirm/executing states
-- ============================================================================

local CommandPage = {}
local spinnerAngle = 0

local function createSpinner(parent)
  local r = 20
  local wrapper = parent:box({
    flexFlow = lvgl.FLOW_ROW,
    flexPad = lvgl.PAD_MEDIUM,
    color = COLOR_THEME_PRIMARY2,
    w = lvgl.PERCENT_SIZE + 100,
    align = CENTER,
  })
  wrapper:arc({
    radius = r,
    thickness = 4,
    rounded = true,
    color = COLOR_THEME_PRIMARY1,
    startAngle = function()
      spinnerAngle = (spinnerAngle + 8) % 360
      return spinnerAngle
    end,
    endAngle = function()
      return spinnerAngle + 120
    end,
  })
end

function CommandPage.showConfirm(name, info, onConfirm, onCancel)
  lvgl.clear()
  local pg = lvgl.page({
    title = "ExpressLRS",
    subtitle = "Send command",
    back = onCancel,
  })

  local container = pg:box({
    w = lvgl.PERCENT_SIZE + 100,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_MEDIUM,
    align = CENTER,
    borderPad = { left = lvgl.PAD_TINY, right = lvgl.PAD_TINY },
  })

  container:build({
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_LARGE,
      thickness = 0,
    },
    {
      type = lvgl.LABEL,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      font = BOLD,
      text = name or "Command",
    },
    {
      type = lvgl.LABEL,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      color = COLOR_THEME_DISABLED,
      text = info or "",
    },
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_LARGE,
      thickness = 0,
    },
    {
      type = lvgl.BOX,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_SMALL,
      borderPad = lvgl.PAD_OUTLINE,
      children = {
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 49,
          text = "Confirm",
          press = onConfirm,
        },
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 49,
          text = "Cancel",
          press = onCancel,
        },
      },
    },
  })

  return pg
end

function CommandPage.showExecuting(title, onCancel)
  lvgl.clear()
  local pg = lvgl.page({
    title = "ExpressLRS",
    subtitle = title or "Executing...",
    back = onCancel,
  })

  local container = pg:box({
    w = lvgl.PERCENT_SIZE + 100,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_MEDIUM,
    align = CENTER,
    borderPad = { left = lvgl.PAD_TINY, right = lvgl.PAD_TINY },
  })

  container:build({
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_LARGE,
      thickness = 0,
    },
  })
  createSpinner(container)
  container:build({
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_LARGE,
      thickness = 0,
    },
    {
      type = lvgl.LABEL,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      color = COLOR_THEME_DISABLED,
      text = "Hold [RTN] to exit and keep running",
    },
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_LARGE,
      thickness = 0,
    },
    {
      type = lvgl.BOX,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_SMALL,
      borderPad = lvgl.PAD_OUTLINE,
      children = {
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 100,
          text = "Cancel command",
          press = onCancel,
        },
      },
    },
  })

  return pg
end

-- ============================================================================
-- EdgeTX version check
-- ============================================================================

local versionCheckResult = nil

local function checkEdgeTxVersion()
  local ver, _radio, maj, minor, rev = getVersion()

  if maj >= 3 then
    return true
  elseif maj == 2 and minor >= 13 then
    return true
  elseif maj == 2 and minor == 12 then
    local rc = string.match(ver, "%-rc(%d+)")
    if rc then
      return tonumber(rc) >= 4
    end
    return true
  elseif maj == 2 and minor == 11 and rev >= 5 then
    return true
  end

  return false
end

local function showVersionRequired()
  lvgl.clear()

  local dg = lvgl.dialog({
    title = "EdgeTX Version Not Supported",
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_SMALL,
    close = function()
      App.shouldExit = true
    end,
  })

  dg:build({
    {
      type = "box",
      x = 10,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_SMALL,
      children = {
        { type = "label", text = "Requires EdgeTX:" },
        { type = "label", text = "- 2.11.5 or later" },
        { type = "label", text = "- 2.12-rc4 or later" },
        { type = "label", text = "- 3.0 or later" },
      },
    },
    {
      type = "box",
      flexFlow = lvgl.FLOW_ROW,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      children = {
        {
          type = "button",
          text = "Exit",
          w = lvgl.PERCENT_SIZE + 98,
          press = function()
            dg:close()
            App.shouldExit = true
          end,
        },
      },
    },
  })
end

local function showLvglRequired()
  lcd.clear()
  lcd.drawText(5, 10, "LVGL support required", BOLD)
  lcd.drawText(5, 20, "Color LCD radio with", 0)
  lcd.drawText(5, 30, "EdgeTX 2.11.5+, 2.12-rc4+,", 0)
  lcd.drawText(5, 40, "or 3.0+ needed", 0)
end

-- ============================================================================
-- Interface: init
-- ============================================================================

function UI.init()
  if lvgl == nil then
    return
  end
  if VERSION_CHECK_ENABLED then
    versionCheckResult = checkEdgeTxVersion()
  end
end

-- ============================================================================
-- Interface: preCheck (LVGL-specific: version/availability)
-- ============================================================================

function UI.preCheck()
  if lvgl == nil then
    showLvglRequired()
    return 0
  end

  if versionCheckResult == false then
    if not UI.uiBuilt then
      showVersionRequired()
      UI.uiBuilt = true
    end
    if App.shouldExit then
      return 2
    end
    return 0
  end

  return nil
end

-- ============================================================================
-- Interface: invalidate
-- ============================================================================

function UI.invalidate()
  UI.uiBuilt = false
end

-- ============================================================================
-- Interface: onDeviceLoaded
-- ============================================================================

function UI.onDeviceLoaded()
  UI.invalidate()
end

-- ============================================================================
-- Interface: onNewDevice
-- ============================================================================

function UI.onNewDevice()
  if Navigation.getCurrent() == Navigation.FOLDER_OTHER_DEVICES or UI.folderWasReady then
    UI.invalidate()
  end
end

-- ============================================================================
-- Interface: handleNoModule
-- ============================================================================

function UI.handleNoModule()
  if not UI.uiBuilt then
    NoModuleDialog.show(function()
      App.shouldExit = true
    end)
    UI.uiBuilt = true
  end
end

-- ============================================================================
-- Interface: handleUnsupported
-- ============================================================================

function UI.handleUnsupported()
  if not UI.uiBuilt then
    Dialogs.showMessage({
      title = "Unsupported Firmware",
      message = "ELRS 1.x firmware detected. Please update to 3.x.",
    })
    UI.uiBuilt = true
  end
end

-- ============================================================================
-- User action handlers (call App for business logic)
-- ============================================================================

function UI.openFolder(folderId, folderName)
  App.enterFolder(folderId, folderName)
  UI.invalidate()
end

function UI.switchDevice(deviceId)
  if App.switchDevice(deviceId) then
    UI.invalidate()
  end
end

function UI.handleBack()
  if Navigation.isAtRoot() then
    Dialogs.showConfirm({
      title = "Exit",
      message = "Exit ExpressLRS Lua script?",
      onConfirm = function()
        App.shouldExit = true
      end,
    })
  else
    local entry = App.goBack()
    if entry and entry.type == Navigation.TYPE_DEVICE and entry.prevDeviceId then
      local prevDevice = Protocol.getDevice(entry.prevDeviceId)
      if prevDevice then
        Protocol.setDevice(prevDevice)
      end
    end
    UI.invalidate()
  end
end

-- ============================================================================
-- Command popup handling
-- ============================================================================

local function onCommandCancel()
  Protocol.commandCancel()
  UI.commandDialog = nil
  UI.invalidate()
end

local function handleCommandPopup()
  if not Protocol.fieldPopup then
    if UI.commandDialog then
      UI.commandDialog = nil
      UI.invalidate()
    end
    return
  end

  if
    Protocol.fieldPopup.status == Protocol.CRSF.CMD_IDLE and Protocol.fieldPopup.lastStatus ~= Protocol.CRSF.CMD_IDLE
  then
    Protocol.reloadAllFields()
    Protocol.fieldPopup = nil
    UI.commandDialog = nil
    UI.invalidate()
  elseif Protocol.fieldPopup.status == Protocol.CRSF.CMD_ASKCONFIRM then
    if not UI.commandDialog or Protocol.fieldPopup.lastStatus ~= Protocol.CRSF.CMD_ASKCONFIRM then
      UI.commandDialog = CommandPage.showConfirm(Protocol.fieldPopup.name, Protocol.fieldPopup.info, function()
        Protocol.commandConfirm()
      end, onCommandCancel)
    end
    Protocol.fieldPopup.lastStatus = Protocol.fieldPopup.status
  elseif Protocol.fieldPopup.status == Protocol.CRSF.CMD_EXECUTING then
    if not UI.commandDialog or Protocol.fieldPopup.lastStatus ~= Protocol.CRSF.CMD_EXECUTING then
      UI.commandDialog =
        CommandPage.showExecuting(Protocol.fieldPopup.name or Protocol.fieldPopup.info, onCommandCancel)
    end
    Protocol.fieldPopup.lastStatus = Protocol.fieldPopup.status
  end
end

-- ============================================================================
-- Warning handling
-- ============================================================================

local function handleWarning()
  if App.shouldExit then
    return
  end
  if Protocol.elrsFlags > Protocol.CRSF.ELRS_FLAGS_STATUS_MASK then
    if not UI.warningDialog and not UI.warningDismissed then
      if Protocol.elrsFlagsInfo == "Model Mismatch" then
        UI.warningDialog = ModelMismatchDialog.show(function()
          UI.warningDismissed = true
          UI.warningDismissedAt = getTime()
          UI.invalidate()
        end, function()
          UI.warningDismissed = true
          App.shouldExit = true
        end)
      else
        Dialogs.showMessage({
          title = "Warning",
          message = Protocol.elrsFlagsInfo,
        })
        UI.warningDialog = true
        UI.warningDismissed = true
        UI.warningDismissedAt = getTime()
      end
    end
    if UI.warningDismissed and UI.warningDismissedAt then
      if getTime() - UI.warningDismissedAt > 6000 then
        UI.warningDismissed = false
        UI.warningDismissedAt = nil
        UI.warningDialog = nil
      end
    end
  else
    UI.warningDialog = nil
    if not UI.warningDismissedAt or (getTime() - UI.warningDismissedAt > 6000) then
      UI.warningDismissed = false
      UI.warningDismissedAt = nil
    end
  end
end

-- ============================================================================
-- Interface: render
-- ============================================================================

function UI.render(_event, _touchState)
  handleCommandPopup()

  if not UI.commandDialog then
    handleWarning()

    local currentFolder = Navigation.getCurrent()
    local folderReady = Protocol.isFolderLoaded(currentFolder)
    if folderReady and not UI.folderWasReady then
      if UI.uiBuilt then
        UI.invalidate()
      end
    end

    if not UI.uiBuilt and #Protocol.fields > 0 then
      UI.build()
    end
  end
end

-- ============================================================================
-- Subtitle builder
-- ============================================================================

function UI.getSubtitle()
  if not Navigation.isAtRoot() then
    local top = Navigation.stack[#Navigation.stack]
    local subtitleParts = { top.name or "" }

    local loaded, total = Protocol.getFolderLoadProgress(Navigation.getCurrent())
    if loaded and loaded < total then
      subtitleParts[#subtitleParts + 1] = string.format(" • Loading %d%%", math.floor(loaded / total * 100))
    end

    return table.concat(subtitleParts)
  end

  local loaded, total = Protocol.getFolderLoadProgress(nil)
  if loaded and loaded < total and Protocol.fieldsCount > 0 then
    return string.format("Loading %d%%", math.floor(loaded / total * 100))
  end

  local subtitle = ""
  if Protocol.receivedPackets then
    local state = Protocol.isConnected() and "Connected" or "No link"
    subtitle = string.format("%u/%u • %s", Protocol.lostPackets, Protocol.receivedPackets, state)
  end

  if
    Protocol.elrsFlags > Protocol.CRSF.ELRS_FLAGS_STATUS_MASK
    and Protocol.elrsFlagsInfo
    and Protocol.elrsFlagsInfo ~= ""
  then
    if subtitle ~= "" then
      subtitle = table.concat({ subtitle, " • ", Protocol.elrsFlagsInfo })
    else
      subtitle = Protocol.elrsFlagsInfo
    end
  end

  return subtitle
end

-- ============================================================================
-- Field value increment
-- ============================================================================

function UI.incrField(field, step)
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

function UI.isBooleanField(field)
  if not field.values or #field.values ~= 2 then
    return false
  end
  return field.values[1] == "Off" and field.values[2] == "On"
end

-- ============================================================================
-- Widget creators
-- ============================================================================

local IS_NARROW = LCD_W < 400
local LABEL_PCT = lvgl.PERCENT_SIZE + (IS_NARROW and 42 or 50)

function UI.createToggleRow(pg, field)
  pg:setting({
    w = lvgl.PERCENT_SIZE + 100,
    title = field.name,
    children = {
      {
        type = lvgl.BOX,
        x = LABEL_PCT,
        flexFlow = lvgl.FLOW_ROW,
        flexPad = lvgl.PAD_MEDIUM,
        align = LEFT,
        children = {
          {
            type = lvgl.TOGGLE,
            get = function()
              return field.value or 0
            end,
            set = function(val)
              field.value = val
              Protocol.fieldIntSave(field)
              Protocol.reloadRelatedFields(field)
            end,
            active = function()
              return not field.disabled
            end,
          },
          {
            type = lvgl.BOX,
            h = lvgl.UI_ELEMENT_HEIGHT,
            children = {
              {
                type = lvgl.LABEL,
                y = lvgl.PAD_MEDIUM,
                text = field.unit,
              },
            },
          },
        },
      },
    },
  })
end

function UI.createChoiceRow(pg, field)
  local filteredValues = {}
  local origToFiltered = {}
  local filteredToOrig = {}
  for i, v in ipairs(field.values or {}) do
    if v ~= "" then
      filteredValues[#filteredValues + 1] = v
      origToFiltered[i - 1] = #filteredValues
      filteredToOrig[#filteredValues] = i - 1
    end
  end

  pg:setting({
    w = lvgl.PERCENT_SIZE + 100,
    title = field.name,
    children = {
      {
        type = lvgl.BOX,
        x = LABEL_PCT,
        flexFlow = lvgl.FLOW_ROW,
        flexPad = lvgl.PAD_MEDIUM,
        align = LEFT,
        children = {
          {
            type = lvgl.CHOICE,
            values = filteredValues,
            get = function()
              return origToFiltered[field.value or 0] or 1
            end,
            set = function(val)
              field.value = filteredToOrig[val] or 0
              Protocol.fieldIntSave(field)
              Protocol.reloadRelatedFields(field)
            end,
            active = function()
              return not field.disabled
            end,
          },
          {
            type = lvgl.BOX,
            h = lvgl.UI_ELEMENT_HEIGHT,
            children = {
              {
                type = lvgl.LABEL,
                y = lvgl.PAD_MEDIUM,
                text = field.unit,
              },
            },
          },
        },
      },
    },
  })
end

function UI.createNumberRow(pg, field)
  pg:build({
    {
      type = lvgl.SETTING,
      w = lvgl.PERCENT_SIZE + 100,
      title = field.name,
      children = {
        {
          type = lvgl.NUMBER_EDIT,
          x = LABEL_PCT,
          min = field.min or 0,
          max = field.max or 255,
          get = function()
            return field.value or 0
          end,
          set = function(val)
            field.value = val
          end,
          edited = function(val)
            field.value = val
            Protocol.fieldIntSave(field)
            Protocol.reloadParentFolder(field)
          end,
          display = function(val)
            if field.type == Protocol.CRSF.FLOAT then
              return string.format(field.fmt or "%.0f", val / (field.prec or 1))
            end
            return table.concat({ tostring(val), field.unit or "" })
          end,
          active = function()
            return not field.disabled
          end,
        },
      },
    },
  })
end

function UI.createInfoRow(pg, field)
  pg:build({
    {
      type = lvgl.SETTING,
      w = lvgl.PERCENT_SIZE + 100,
      title = field.name,
      children = {
        {
          type = lvgl.LABEL,
          x = LABEL_PCT,
          text = field.value,
        },
      },
    },
  })
end

function UI.createFolderWidget(pg, field, width)
  pg:button({
    text = field.name or "",
    w = width or (lvgl.PERCENT_SIZE + 100),
    h = lvgl.UI_ELEMENT_HEIGHT * 2,
    press = function()
      UI.openFolder(field.id, field.name)
    end,
  })
end

function UI.createCommandWidget(pg, field)
  pg:button({
    text = field.name or "",
    w = lvgl.PERCENT_SIZE + 100,
    press = function()
      Protocol.handleCommandSave(field)
    end,
  })
end

function UI.buildFieldWidget(pg, field, folderWidth)
  if not field or not field.name then
    return
  end

  local fieldType = field.type

  if fieldType == Protocol.CRSF.FOLDER then
    return UI.createFolderWidget(pg, field, folderWidth)
  end

  if fieldType == Protocol.CRSF.COMMAND then
    return UI.createCommandWidget(pg, field)
  end

  if fieldType <= Protocol.CRSF.INT16 or fieldType == Protocol.CRSF.FLOAT then
    return UI.createNumberRow(pg, field)
  end

  if fieldType == Protocol.CRSF.TEXT_SELECTION then
    if UI.isBooleanField(field) then
      return UI.createToggleRow(pg, field)
    else
      return UI.createChoiceRow(pg, field)
    end
  end

  if fieldType == Protocol.CRSF.STRING or fieldType == Protocol.CRSF.INFO then
    return UI.createInfoRow(pg, field)
  end
end

-- ============================================================================
-- Main build function
-- ============================================================================

function UI.build()
  lvgl.clear()

  local pageOptions = {
    title = "ExpressLRS",
    subtitle = UI.getSubtitle,
  }

  if not Navigation.isAtRoot() then
    pageOptions.backButton = true
    pageOptions.back = function()
      UI.handleBack()
    end
  else
    pageOptions.back = UI.handleBack
  end

  UI.currentPage = lvgl.page(pageOptions)

  local fieldContainer = UI.currentPage:box({
    w = lvgl.PERCENT_SIZE + 100,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_OUTLINE,
  })

  local currentFolder = Navigation.getCurrent()

  if currentFolder == Navigation.FOLDER_OTHER_DEVICES then
    for _, device in ipairs(Protocol.devices) do
      if device.id ~= Protocol.deviceId then
        fieldContainer:button({
          text = device.name or "Unknown",
          w = lvgl.PERCENT_SIZE + 100,
          press = function()
            UI.switchDevice(device.id)
          end,
        })
      end
    end
  else
    if currentFolder == nil then
      UI.createInfoRow(fieldContainer, { name = "Device", value = Protocol.deviceName or "Searching..." })
    end

    local fieldsInFolder = Protocol.getFieldsInFolder(currentFolder)
    local FOLDERS_PER_ROW = 2
    if IS_NARROW then
      FOLDERS_PER_ROW = 1
    elseif LCD_W >= 800 then
      FOLDERS_PER_ROW = 3
    end
    local folderWidth = math.floor(100 / FOLDERS_PER_ROW) - 1
    local i = 1
    while i <= #fieldsInFolder do
      local field = fieldsInFolder[i]

      if field.type == Protocol.CRSF.FOLDER then
        local folderBatch = {}
        while i <= #fieldsInFolder and fieldsInFolder[i].type == Protocol.CRSF.FOLDER do
          folderBatch[#folderBatch + 1] = fieldsInFolder[i]
          i = i + 1
        end

        if FOLDERS_PER_ROW == 1 then
          for j = 1, #folderBatch do
            UI.createFolderWidget(fieldContainer, folderBatch[j])
          end
        else
          for j = 1, #folderBatch, FOLDERS_PER_ROW do
            local rowContainer = fieldContainer:box({
              w = lvgl.PERCENT_SIZE + 100,
              borderPad = lvgl.PAD_OUTLINE,
              flexFlow = lvgl.FLOW_ROW,
              flexPad = lvgl.PAD_SMALL,
              align = CENTER,
              color = COLOR_THEME_PRIMARY2,
            })

            for k = 0, FOLDERS_PER_ROW - 1 do
              local folderField = folderBatch[j + k]
              if folderField then
                UI.createFolderWidget(rowContainer, folderField, lvgl.PERCENT_SIZE + folderWidth)
              end
            end
          end
        end
      else
        UI.buildFieldWidget(fieldContainer, field)
        i = i + 1
      end
    end

    if currentFolder == nil and Protocol.deviceIsELRS_TX then
      UI.createInfoRow(fieldContainer, { name = "Lua script version", value = VERSION })
    end

    if currentFolder == nil and #Protocol.devices > 1 and not Navigation.hasDeviceEntry() then
      fieldContainer:button({
        text = "Other Devices",
        w = lvgl.PERCENT_SIZE + 100,
        h = lvgl.UI_ELEMENT_HEIGHT * 2,
        press = function()
          UI.openFolder(Navigation.FOLDER_OTHER_DEVICES, "Other Devices")
        end,
      })
    end
  end

  fieldContainer:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    h = lvgl.PAD_SMALL,
    thickness = 0,
  })

  UI.uiBuilt = true
end

return UI
