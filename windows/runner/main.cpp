#include "startup.h"
#include <algorithm>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const auto arguments = GetCommandLineArguments();
  const auto has = [&](const char* flag) { return std::find(arguments.begin(), arguments.end(), flag) != arguments.end(); };
  if (has("--enable-startup")) return static_cast<int>(suite::SetStartup(L"Pulse", true));
  if (has("--disable-startup")) return static_cast<int>(suite::SetStartup(L"Pulse", false));
  if (has("--startup-status")) return suite::StartupEnabled(L"Pulse") ? 0 : 1;
  if (has("--exit")) { if (HWND existing = FindWindowW(nullptr, L"Pulse")) PostMessage(existing, WM_APP+13, 0, 0); return 0; }
  HANDLE single_instance = CreateMutexW(nullptr, TRUE, L"Local\\PulseBatteryDesktop");
  if (single_instance && GetLastError() == ERROR_ALREADY_EXISTS) {
    if (HWND existing = FindWindowW(nullptr, L"Pulse")) {
      if (has("--widget")) PostMessage(existing, WM_APP+11, 0, 0);
      else if (!has("--startup")) { ShowWindow(existing, SW_RESTORE); SetForegroundWindow(existing); }
    }
    CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  command_line_arguments.erase(std::remove(command_line_arguments.begin(), command_line_arguments.end(), "--widget"), command_line_arguments.end());
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartupMode(has("--startup") || has("--widget"), has("--widget"));
  Win32Window::Point origin(100, 70);
  Win32Window::Size size(1060, 820);
  if (!window.Create(L"Pulse", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance) CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
