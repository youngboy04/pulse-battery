#include "startup.h"
#include "flutter_window.h"
#include <algorithm>
#include <optional>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <dwmapi.h>
#include <dbt.h>
#include "resource.h"
#include "flutter/generated_plugin_registrant.h"

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
constexpr wchar_t kPreferences[] = L"Software\\Pulse";
DWORD ReadPreference(const wchar_t* name, DWORD fallback) {
  DWORD value = fallback, bytes = sizeof(value);
  RegGetValueW(HKEY_CURRENT_USER, kPreferences, name, RRF_RT_REG_DWORD,
               nullptr, &value, &bytes);
  return value;
}
void WritePreference(const wchar_t* name, DWORD value) {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kPreferences, 0, nullptr, 0,
      KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    RegSetValueExW(key, name, 0, REG_DWORD,
      reinterpret_cast<const BYTE*>(&value), sizeof(value));
    RegCloseKey(key);
  }
}
std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
    static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}
const Value* Field(const Value& object, const char* key) {
  const auto* map = std::get_if<Map>(&object);
  if (!map) return nullptr;
  const auto found = map->find(Value(key));
  return found == map->end() ? nullptr : &found->second;
}
const flutter::EncodableList& Devices(const Value& snapshot) {
  static const flutter::EncodableList empty;
  const auto* value = Field(snapshot, "devices");
  const auto* list = value ? std::get_if<flutter::EncodableList>(value) : nullptr;
  return list ? *list : empty;
}
std::wstring DeviceLabel(const Value& device) {
  const auto* name = Field(device, "name");
  const auto* text = name ? std::get_if<std::string>(name) : nullptr;
  std::wstring out = text ? Wide(*text) : L"HID";
  out += L": ";
  const auto* battery = Field(device, "battery");
  const auto* percent = battery ? std::get_if<int32_t>(battery) : nullptr;
  out += percent ? std::to_wstring(*percent) + L"%" : L"—";
  const auto* fresh = Field(device, "fresh");
  const bool current = fresh && std::get_if<bool>(fresh) && std::get<bool>(*fresh);
  const auto* status = Field(device, "status");
  const auto* label = status ? std::get_if<std::string>(status) : nullptr;
  if (!current && label) out += L" · " + Wide(*label);
  return out;
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project, int mode, FlutterWindow* owner)
    : project_(project), mode_(mode), owner_(owner) {
  pinned_ = ReadPreference(L"WidgetPinned", 0) != 0;
}
FlutterWindow::~FlutterWindow() { Destroy(); }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  if (mode_ != 0) {
    SetWindowLongPtr(GetHandle(), GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
    SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, WS_EX_TOOLWINDOW);
    const DWORD round = 2;
    DwmSetWindowAttribute(GetHandle(), 33, &round, sizeof(round));
    PlaceCompact();
  }
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
    frame.right-frame.left, frame.bottom-frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  BOOL dark = TRUE;
  DwmSetWindowAttribute(GetHandle(), 20, &dark, sizeof(dark));

  if (mode_ == 0) {
    DEV_BROADCAST_DEVICEINTERFACE_W filter{};
    filter.dbcc_size = sizeof(filter);
    filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
    filter.dbcc_classguid = {0x4d1e55b2, 0xf16f, 0x11cf,
      {0x88, 0xcb, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30}};
    device_notifications_ = RegisterDeviceNotificationW(
      GetHandle(), &filter, DEVICE_NOTIFY_WINDOW_HANDLE);
    tray_.cbSize = sizeof(tray_); tray_.hWnd = GetHandle(); tray_.uID = 1;
    tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    tray_.uCallbackMessage = WM_APP + 10;
    tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    wcscpy_s(tray_.szTip, L"Pulse");
    Shell_NotifyIconW(NIM_ADD, &tray_);
  }
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
    flutter_controller_->engine()->messenger(), "pulse/desktop",
    &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    auto* root = owner_ ? owner_ : this;
    const auto& method = call.method_name();
    if (method == "getStartup") {
      result->Success(Value(suite::StartupEnabled(L"Pulse")));
    } else if (method == "setStartup" && call.arguments()) {
      const auto* enabled = std::get_if<bool>(call.arguments());
      if (!enabled) { result->Error("invalid_argument", "Expected boolean"); return; }
      const auto status = suite::SetStartup(L"Pulse", *enabled);
      if (status != ERROR_SUCCESS) result->Error("startup_failed", std::to_string(status));
      else result->Success();
    } else if (method == "publish" && mode_ == 0 && call.arguments()) {
      UpdateSnapshot(*call.arguments()); result->Success();
    } else if (method == "getSnapshot") {
      result->Success(root->snapshot_);
    } else if (method == "getPinned") {
      result->Success(Value(pinned_));
    } else if (method == "getWidgetTheme") {
      const auto selected = ReadPreference(L"WidgetTheme", 0);
      result->Success(Value(static_cast<int32_t>(selected < 4 ? selected : 0)));
    } else if (method == "setWidgetTheme" && call.arguments()) {
      const auto* theme = std::get_if<int32_t>(call.arguments());
      if (!theme || *theme < 0 || *theme > 3) {
        result->Error("invalid_theme", "Unknown widget theme");
        return;
      }
      WritePreference(L"WidgetTheme", static_cast<DWORD>(*theme));
      for (auto* window : {root, root->widget_.get(), root->flyout_.get()}) {
        if (window && window->channel_) window->channel_->InvokeMethod(
          "widgetThemeChanged", std::make_unique<Value>(*theme));
      }
      result->Success();
    } else if (method == "showWidget") {
      root->ShowCompact(1); result->Success();
    } else if (method == "openMain") {
      if (mode_ == 2) ShowWindow(GetHandle(), SW_HIDE);
      ShowWindow(root->GetHandle(), SW_RESTORE); SetForegroundWindow(root->GetHandle());
      result->Success();
    } else if (method == "refresh") {
      if (root->channel_) root->channel_->InvokeMethod("refresh", nullptr);
      result->Success();
    } else if (method == "drag" && mode_ == 1) {
      ReleaseCapture();
      PostMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
      result->Success();
    } else if (method == "togglePin" && mode_ == 1) {
      pinned_ = !pinned_; WritePreference(L"WidgetPinned", pinned_ ? 1 : 0);
      SetWindowPos(GetHandle(), pinned_ ? HWND_TOPMOST : HWND_NOTOPMOST,
        0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      result->Success(Value(pinned_));
    } else if (method == "hide" || method == "hideToTray") {
      HideCompact(); result->Success();
    } else if (method == "notify" && call.arguments()) {
      const auto* message = std::get_if<std::string>(call.arguments());
      if (message) {
        root->tray_.uFlags |= NIF_INFO;
        wcscpy_s(root->tray_.szInfoTitle, L"Pulse");
        wcsncpy_s(root->tray_.szInfo, Wide(*message).c_str(), _TRUNCATE);
        root->tray_.dwInfoFlags = NIIF_INFO;
        Shell_NotifyIconW(NIM_MODIFY, &root->tray_);
        root->tray_.uFlags &= ~NIF_INFO;
      }
      result->Success();
    } else result->NotImplemented();
  });
  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (mode_ == 1) ShowWindow(GetHandle(), SW_SHOWNOACTIVATE);
    else if (mode_ != 0 || !startup_) { Show(); if (mode_ == 2) SetForegroundWindow(GetHandle()); }
    if (mode_ == 0 && (force_widget_ || ReadPreference(L"WidgetVisible", 1))) PostMessage(GetHandle(), WM_APP+11, 0, 0);
  });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::PlaceCompact() {
  POINT point{};
  GetCursorPos(&point);
  if (mode_ == 1) {
    point.x = static_cast<LONG>(ReadPreference(L"WidgetX", 100));
    point.y = static_cast<LONG>(ReadPreference(L"WidgetY", 100));
  }
  MONITORINFO monitor{}; monitor.cbSize = sizeof(monitor);
  GetMonitorInfo(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST), &monitor);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST));
  const int width = MulDiv(360, dpi, 96), height = MulDiv(282, dpi, 96);
  const auto& work = monitor.rcWork;
  int x = point.x-width/2, y = point.y-height-12;
  if (mode_ == 1) {
    x = static_cast<LONG>(ReadPreference(L"WidgetX", work.right-width-24));
    y = static_cast<LONG>(ReadPreference(L"WidgetY", work.top+24));
  }
  x = std::clamp(x, static_cast<int>(work.left), std::max(static_cast<int>(work.left), static_cast<int>(work.right)-width));
  y = std::clamp(y, static_cast<int>(work.top), std::max(static_cast<int>(work.top), static_cast<int>(work.bottom)-height));
  SetWindowPos(GetHandle(), mode_ == 2 || pinned_ ? HWND_TOPMOST : HWND_NOTOPMOST,
    x, y, width, height, SWP_FRAMECHANGED | SWP_NOACTIVATE);
}

void FlutterWindow::ShowCompact(int mode) {
  auto& child = mode == 1 ? widget_ : flyout_;
  if (!child) {
    flutter::DartProject project(L"data");
    project.set_dart_entrypoint_arguments({mode == 1 ? "--widget" : "--tray"});
    child = std::make_unique<FlutterWindow>(project, mode, this);
    if (!child->Create(mode == 1 ? L"Pulse Widget" : L"Pulse Tray", Point(100,100), Size(360,282))) {
      child.reset(); return;
    }
    child->SetQuitOnClose(false);
  } else {
    child->PlaceCompact();
    ShowWindow(child->GetHandle(), mode == 1 ? SW_SHOWNOACTIVATE : SW_SHOW);
    if (mode == 2) SetForegroundWindow(child->GetHandle());
  }
  if (mode == 1) WritePreference(L"WidgetVisible", 1);
}

void FlutterWindow::HideCompact() {
  ShowWindow(GetHandle(), SW_HIDE);
  if (mode_ == 1) WritePreference(L"WidgetVisible", 0);
}

void FlutterWindow::UpdateSnapshot(const Value& snapshot) {
  snapshot_ = snapshot;
  for (auto* child : {widget_.get(), flyout_.get()}) {
    if (child && child->channel_) child->channel_->InvokeMethod("snapshot", std::make_unique<Value>(snapshot));
  }
  const auto& devices = Devices(snapshot);
  auto tooltip = L"Pulse · устройств: " + std::to_wstring(devices.size());
  for (size_t i = 0; i < devices.size() && i < 2; ++i) tooltip += L"\n" + DeviceLabel(devices[i]);
  wcsncpy_s(tray_.szTip, tooltip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &tray_);
}

void FlutterWindow::OnDestroy() {
  if (device_notifications_) {
    UnregisterDeviceNotification(device_notifications_);
    device_notifications_ = nullptr;
  }
  widget_.reset(); flyout_.reset();
  if (tray_.hWnd) { Shell_NotifyIconW(NIM_DELETE, &tray_); tray_.hWnd = nullptr; }
  channel_.reset(); flutter_controller_.reset();
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  static const UINT taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
  if (message == taskbarCreated && mode_ == 0 && tray_.hWnd) {
    Shell_NotifyIconW(NIM_ADD, &tray_); return 0;
  }
  // Native lifecycle handling precedes Flutter, which can consume focus messages.
  if (message == WM_DEVICECHANGE && mode_ == 0 && channel_ &&
      (wparam == DBT_DEVICEARRIVAL || wparam == DBT_DEVICEREMOVECOMPLETE ||
       wparam == DBT_DEVNODES_CHANGED)) {
    channel_->InvokeMethod("devicesChanged", nullptr);
  }
  if (message == WM_CLOSE) { HideCompact(); return 0; }
  if (message == WM_ACTIVATE && mode_ == 2 && LOWORD(wparam) == WA_INACTIVE) {
    ShowWindow(hwnd, SW_HIDE);
  }
  if (message == WM_EXITSIZEMOVE && mode_ == 1) {
    RECT rect{}; GetWindowRect(hwnd, &rect);
    WritePreference(L"WidgetX", static_cast<DWORD>(rect.left));
    WritePreference(L"WidgetY", static_cast<DWORD>(rect.top));
  }
  if (message == WM_APP+13) { Destroy(); return 0; }
  if (message == WM_APP+11) { ShowCompact(1); return 0; }
  if (message == WM_APP+10 && mode_ == 0) {
    if (lparam == WM_LBUTTONUP) {
      if (flyout_ && IsWindowVisible(flyout_->GetHandle())) flyout_->HideCompact();
      else ShowCompact(2);
    } else if (lparam == WM_LBUTTONDBLCLK) {
      ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd);
    } else if (lparam == WM_RBUTTONUP) {
      POINT point; GetCursorPos(&point);
      HMENU menu = CreatePopupMenu();
      const auto& devices = Devices(snapshot_);
      if (devices.empty()) AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"Добавьте устройства в Pulse");
      for (size_t i = 0; i < devices.size() && i < 12; ++i)
        AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, DeviceLabel(devices[i]).c_str());
      if (devices.size() > 12)
        AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"Остальные устройства — в Pulse");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, 1, L"Открыть Pulse");
      AppendMenuW(menu, MF_STRING, 3, L"Обновить заряд");
      const bool visible = widget_ && IsWindowVisible(widget_->GetHandle());
      AppendMenuW(menu, MF_STRING | (visible ? MF_CHECKED : 0), 4, L"Виджет на рабочем столе");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, 2, L"Выход");
      SetForegroundWindow(hwnd);
      const int action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu); PostMessage(hwnd, WM_NULL, 0, 0);
      if (action == 1) { ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd); }
      if (action == 3 && channel_) channel_->InvokeMethod("refresh", nullptr);
      if (action == 4) { if (visible) widget_->HideCompact(); else ShowCompact(1); }
      if (action == 2) Destroy();
    }
    return 0;
  }
  if (message == WM_GETMINMAXINFO && mode_ == 0) {
    auto limits = reinterpret_cast<MINMAXINFO*>(lparam);
    const UINT dpi = GetDpiForWindow(hwnd);
    limits->ptMinTrackSize.x = MulDiv(680, dpi, 96);
    limits->ptMinTrackSize.y = MulDiv(580, dpi, 96);
    return 0;
  }
  if (flutter_controller_) {
    auto result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
    if (message == WM_FONTCHANGE) flutter_controller_->engine()->ReloadSystemFonts();
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
