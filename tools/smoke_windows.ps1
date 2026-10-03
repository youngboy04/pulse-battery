param([Parameter(Mandatory=$true)][int]$PulseProcessId)
$ErrorActionPreference = 'Stop'
# Native window-lifecycle integration checks, scoped to this application's PID.
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PulseWindowTest {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr param);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr param);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
  public static IntPtr Find(int target, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hwnd,param) => {
      uint pid; GetWindowThreadProcessId(hwnd,out pid);
      if(pid == target) {
        var text = new StringBuilder(256); GetWindowText(hwnd,text,256);
        if(text.ToString() == title) found=hwnd;
      }
      return true;
    },IntPtr.Zero);
    return found;
  }
}
'@
function Wait-PulseWindow([string]$Title) {
    for ($attempt=0; $attempt -lt 80; $attempt++) {
        $handle = [PulseWindowTest]::Find($PulseProcessId,$Title)
        if ($handle -ne [IntPtr]::Zero -and [PulseWindowTest]::IsWindowVisible($handle)) { return $handle }
        Start-Sleep -Milliseconds 100
    }
    throw "Visible window not found: $Title"
}
$main = [PulseWindowTest]::Find($PulseProcessId,'Pulse')
if ($main -eq [IntPtr]::Zero) { throw 'Main window not found' }
[PulseWindowTest]::PostMessage($main,0x800B,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
$widget = Wait-PulseWindow 'Pulse Widget'
if (([PulseWindowTest]::GetWindowLongPtr($widget,-20).ToInt64() -band 0x80) -eq 0) { throw 'Widget unexpectedly appears in taskbar' }
[PulseWindowTest]::PostMessage($main,0x10,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 200
if ([PulseWindowTest]::IsWindowVisible($main)) { throw 'Close did not hide main window' }
if (![PulseWindowTest]::IsWindowVisible($widget)) { throw 'Closing main window hid the widget' }
[PulseWindowTest]::PostMessage($main,0x800A,[IntPtr]1,[IntPtr]0x202) | Out-Null
$flyout = Wait-PulseWindow 'Pulse Tray'
[PulseWindowTest]::PostMessage($flyout,6,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 200
if ([PulseWindowTest]::IsWindowVisible($flyout)) { throw 'Tray popup did not hide on deactivation' }
[PulseWindowTest]::PostMessage($widget,0x10,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 200
if ([PulseWindowTest]::IsWindowVisible($widget)) { throw 'Widget close did not hide it' }
if ((Get-ItemPropertyValue HKCU:\Software\Pulse WidgetVisible) -ne 0) { throw 'Widget visibility not saved' }
[PulseWindowTest]::PostMessage($main,0x800B,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
$restored = Wait-PulseWindow 'Pulse Widget'
if ($widget -ne $restored) { throw 'Widget engine was recreated unnecessarily' }
if ((Get-ItemPropertyValue HKCU:\Software\Pulse WidgetVisible) -ne 1) { throw 'Widget restore not saved' }
Get-Process -Id $PulseProcessId | Select-Object Id,ProcessName
Write-Output 'PASS: desktop widget, taskbar style, close-to-tray, flyout, hide/restore, persisted visibility, shared process.'
