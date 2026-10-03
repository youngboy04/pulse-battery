#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         int mode = 0, FlutterWindow* owner = nullptr);
  virtual ~FlutterWindow();
  void SetStartupMode(bool value, bool widget = false) { startup_ = value; force_widget_ = widget; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NOTIFYICONDATAW tray_{};
  HDEVNOTIFY device_notifications_ = nullptr;
  int mode_ = 0; // 0: main, 1: desktop widget, 2: tray flyout.
  FlutterWindow* owner_ = nullptr;
  std::unique_ptr<FlutterWindow> widget_;
  std::unique_ptr<FlutterWindow> flyout_;
  flutter::EncodableValue snapshot_;
  bool pinned_ = false;
  bool startup_ = false;
  bool force_widget_ = false;
  void ShowCompact(int mode);
  void PlaceCompact();
  void UpdateSnapshot(const flutter::EncodableValue& snapshot);
  void HideCompact();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
