-- TNS|ExpressLRS_WM|TNE
---- #########################################################################
---- #                                                                       #
---- # Copyright (C) OpenTX, adapted for ExpressLRS                          #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #                                                                       #
---- # Unified tool for BW and color LCD radios (EdgeTX 2.11+)               #
---- #########################################################################

local VERSION = "r2_WM"
local useLvgl = (lvgl ~= nil)

-- ============================================================================
-- Load shared modules
-- ============================================================================

local shim = loadScript("/SCRIPTS/TOOLS/ExpressLRS/shim.lua")()
local Protocol = loadScript("/SCRIPTS/TOOLS/ExpressLRS/protocol.lua")(shim)
local Navigation = loadScript("/SCRIPTS/TOOLS/ExpressLRS/navigation.lua")()

-- ============================================================================
-- App Module: Pure business logic (zero UI references)
-- ============================================================================

local App = {
  crsfModuleChecked = false,
  crsfModuleFound = false,
  shouldExit = false,
}

function App.reset()
  App.crsfModuleChecked = false
  App.crsfModuleFound = false
  App.shouldExit = false
  Protocol.reset()
end

function App.checkCrsfModule()
  if App.crsfModuleChecked then
    return App.crsfModuleFound
  end
  App.crsfModuleChecked = true
  App.crsfModuleFound = Protocol.hasCrsfModule()
  return App.crsfModuleFound
end

-- Returns true if device was set, false if no change needed.
function App.loadDevice(device)
  if Protocol.setDevice(device) then
    Navigation.reset()
    return true
  end
  return false
end

-- Returns true if device was switched.
function App.switchDevice(deviceId, viewState)
  local device = Protocol.getDevice(deviceId)
  if not device then
    return false
  end
  local prevDeviceId = Protocol.deviceId
  if Protocol.setDevice(device) then
    Navigation.openDevice(device.name, prevDeviceId, viewState)
    return true
  end
  return false
end

-- Navigate into folder.
function App.enterFolder(folderId, folderName, viewState)
  Navigation.openFolder(folderId, folderName, viewState)
  Protocol.loadFolderChildren(folderId)
end

-- Returns navigation entry (or nil).
function App.goBack()
  return Navigation.goBack()
end

-- Reload at root: switch back to TX device or reload fields + ping.
function App.reloadAtRoot()
  if Protocol.deviceId ~= Protocol.CRSF.ADDRESS_CRSF_TRANSMITTER then
    local txDevice = Protocol.getDevice(Protocol.CRSF.ADDRESS_CRSF_TRANSMITTER)
    if txDevice then
      App.loadDevice(txDevice)
    end
  else
    Protocol.allocateFields()
    Protocol.reloadAllFields()
  end
  Protocol.pingDevices()
end

-- ============================================================================
-- Mock data for simulator
-- ============================================================================

local function setMock()
  local _, rv = getVersion()
  if string.sub(rv, -5) ~= "-simu" then
    return
  end
  local mockModule = loadScript("/SCRIPTS/CRSFSimulator/csrfsimulator.lua")
  if mockModule == nil then
    return
  end
  local mock = mockModule()
  Protocol.pop = mock.pop
  Protocol.push = mock.push
  Protocol.hasCrsfModule = function()
    return mock.moduleFound
  end
end

-- ============================================================================
-- UI loading (deferred to init)
-- ============================================================================

local UI

local function init()
  local deps = {
    App = App,
    Navigation = Navigation,
    Protocol = Protocol,
    VERSION = VERSION,
  }
  if useLvgl then
    UI = loadScript("/SCRIPTS/TOOLS/ExpressLRS/ui/lvgl.lua")(deps)
  else
    UI = loadScript("/SCRIPTS/TOOLS/ExpressLRS/ui/lcd.lua")(deps)
  end
  UI.init()
  setMock()
end

-- ============================================================================
-- Run (shared orchestrator)
-- ============================================================================

local function run(event, touchState)
  if event == nil then
    return 2
  end

  -- UI-specific pre-checks (LVGL: version/availability check; BW: not defined)
  if UI.preCheck then
    local result = UI.preCheck()
    if result ~= nil then
      return result
    end
  end

  if not App.checkCrsfModule() then
    UI.handleNoModule()
    if App.shouldExit then
      return 2
    end
    return 0
  end

  local targetDevice, anyNewDevice = Protocol.poll()
  Protocol.tick()

  if Protocol.elrsV1Detected then
    UI.handleUnsupported()
    return 0
  end

  if targetDevice then
    if App.loadDevice(targetDevice) then
      UI.onDeviceLoaded()
    end
  end
  if anyNewDevice then
    UI.onNewDevice()
  end

  local currentFolder = Navigation.getCurrent()
  local folderReady = Protocol.isFolderLoaded(currentFolder)
  if folderReady and not UI.folderWasReady then
    collectgarbage("collect")
    UI.invalidate()
    if currentFolder == nil and not Protocol.backgroundLoading then
      Protocol.startBackgroundLoad()
    end
  end
  UI.folderWasReady = folderReady

  UI.render(event, touchState)

  if App.shouldExit then
    return 2
  end
  return 0
end

-- ============================================================================
-- Return
-- ============================================================================

return { init = init, run = run, useLvgl = useLvgl }
