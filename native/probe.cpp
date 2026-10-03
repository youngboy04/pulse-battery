#include <windows.h>
#include <hidsdi.h>
#include <hidpi.h>
#include <setupapi.h>
#include <initguid.h>
#include <devpkey.h>
#include <iostream>
#include <sstream>
#include <vector>
#include <string>
#include <iomanip>
#include "protocol.h"

std::string utf8(const wchar_t* s) {
  int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s, -1, out.data(), n, nullptr, nullptr);
  if (!out.empty()) out.pop_back();
  return out;
}
std::string quote(const std::string& s) {
  std::ostringstream o; o << '"';
  for (unsigned char c : s) {
    if(c == '"' || c == '\\') o << '\\' << c;
    else if(c < 32) o << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (int)c;
    else o << c;
  }
  o << '"'; return o.str();
}
std::string hex(const std::vector<unsigned char>& b) {
  std::ostringstream o;
  for(auto c:b) o << std::hex << std::setw(2) << std::setfill('0') << (int)c << ' ';
  return o.str();
}
bool transfer(HANDLE h, std::vector<unsigned char>& data, bool write, DWORD timeout) {
  OVERLAPPED ov{}; ov.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);
  if(!ov.hEvent) return false;
  DWORD count=0;
  BOOL ok=write ? WriteFile(h,data.data(),static_cast<DWORD>(data.size()),&count,&ov)
                : ReadFile(h,data.data(),static_cast<DWORD>(data.size()),&count,&ov);
  if(!ok && GetLastError()==ERROR_IO_PENDING) {
    if(WaitForSingleObject(ov.hEvent,timeout)==WAIT_OBJECT_0) ok=GetOverlappedResult(h,&ov,&count,FALSE);
    else { CancelIoEx(h,&ov); GetOverlappedResult(h,&ov,&count,TRUE); ok=FALSE; }
  }
  CloseHandle(ov.hEvent);
  return ok && count==data.size();
}
int main(int argc, char** argv) {
  HANDLE mutex=CreateMutexW(nullptr,FALSE,L"Local\\PulseBatteryRead");
  if(!mutex) return 1;
  const DWORD lock=WaitForSingleObject(mutex,1000);
  if(lock!=WAIT_OBJECT_0 && lock!=WAIT_ABANDONED) {
    CloseHandle(mutex); std::cerr << "Another battery query is running"; return 2;
  }
  bool enumerate = argc > 1 && std::string(argv[1]) == "--list";
  GUID guid; HidD_GetHidGuid(&guid);
  HDEVINFO info = SetupDiGetClassDevsW(&guid,nullptr,nullptr,DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
  if(info == INVALID_HANDLE_VALUE) { std::cerr << "SetupDiGetClassDevs failed"; return 1; }
  std::cout << "["; bool first = true;
  for(DWORD i=0;;i++) {
    SP_DEVICE_INTERFACE_DATA iface{}; iface.cbSize=sizeof(iface);
    if(!SetupDiEnumDeviceInterfaces(info,nullptr,&guid,i,&iface)) break;
    DWORD required=0;
    SetupDiGetDeviceInterfaceDetailW(info,&iface,nullptr,0,&required,nullptr);
    std::vector<unsigned char> buffer(required);
    auto detail=reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buffer.data());
    detail->cbSize=sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
    SP_DEVINFO_DATA device{}; device.cbSize=sizeof(device);
    if(!SetupDiGetDeviceInterfaceDetailW(info,&iface,detail,required,nullptr,&device)) continue;
    GUID container{}; DEVPROPTYPE property_type=0;
    std::string device_id=utf8(detail->DevicePath);
    if(SetupDiGetDevicePropertyW(info,&device,&DEVPKEY_Device_ContainerId,
        &property_type,reinterpret_cast<PBYTE>(&container),sizeof(container),nullptr,0)
        && property_type==DEVPROP_TYPE_GUID && container != GUID_NULL) {
      wchar_t value[40]{};
      if(StringFromGUID2(container,value,40)) device_id=utf8(value);
    }
    HANDLE h=CreateFileW(detail->DevicePath,0,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);
    if(h==INVALID_HANDLE_VALUE) continue;
    HIDD_ATTRIBUTES a{}; a.Size=sizeof(a); HidD_GetAttributes(h,&a);
    wchar_t product[256]{}, manufacturer[256]{};
    HidD_GetProductString(h,product,sizeof(product)); HidD_GetManufacturerString(h,manufacturer,sizeof(manufacturer));
    if(!product[0]) {
      if(!SetupDiGetDeviceRegistryPropertyW(info,&device,SPDRP_FRIENDLYNAME,nullptr,
          reinterpret_cast<PBYTE>(product),sizeof(product),nullptr))
        SetupDiGetDeviceRegistryPropertyW(info,&device,SPDRP_DEVICEDESC,nullptr,
          reinterpret_cast<PBYTE>(product),sizeof(product),nullptr);
    }
    PHIDP_PREPARSED_DATA pp=nullptr; HIDP_CAPS caps{};
    if(HidD_GetPreparsedData(h,&pp)) { HidP_GetCaps(pp,&caps); HidD_FreePreparsedData(pp); }
    bool mouse = a.VendorID==0x3837 && a.ProductID==0x100a && caps.UsagePage==0xff01;
    bool keyboard = a.VendorID==0x05ac && a.ProductID==0x024f && std::wstring(product)==L"Galaxy70-2.4g" && caps.UsagePage==0xff60 && caps.Usage==0x61;
    int battery=-1; int charging=-1; std::string raw, status="unsupported";
    if(mouse && !enumerate) {
      CloseHandle(h);
      h=CreateFileW(detail->DevicePath,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);
      status="access_denied";
      if(h!=INVALID_HANDLE_VALUE && caps.FeatureReportByteLength>=20) {
        auto request=pulse::mouse_request();
        status="no_response";
        {
          for(int retry=0;retry<6;retry++) {
            if(!HidD_SetFeature(h,request.data(),static_cast<ULONG>(request.size()))) break;
            Sleep(120); std::vector<unsigned char> reply(21,0); reply[0]=0x11;
            if(!HidD_GetFeature(h,reply.data(),static_cast<ULONG>(reply.size()))) continue;
            raw=hex(reply);
            if(reply[0]!=0x11 || (reply[1]^0xff)!=0x06) continue;
            const auto reading=pulse::parse_mouse(reply);
            status=reading.status;
            if(status=="asleep") continue;
            battery=reading.percent; charging=reading.charging;
            break;
          }
        }
      }
    }
    if(keyboard && !enumerate) {
      CloseHandle(h);
      h=CreateFileW(detail->DevicePath,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_FLAG_OVERLAPPED,nullptr);
      status="access_denied";
      if(h!=INVALID_HANDLE_VALUE && caps.InputReportByteLength==33 && caps.OutputReportByteLength==33) {
        // Official Galaxy70 driver 1.0.0.0: battery query at VA 0x435EB0.
        // 32-byte payload plus zero report ID; additive checksum at byte 32.
        auto request=pulse::keyboard_request();
        HidD_FlushQueue(h);
        status="no_response";
        if(transfer(h,request,true,400)) {
          for(int retry=0;retry<3;retry++) {
            std::vector<unsigned char> reply(33,0);
            if(!transfer(h,reply,false,400)) break;
            raw=hex(reply);
            if(reply[0]!=0 || reply[1]!=0x20 || reply[2]!=1 || reply[3]!=0) continue;
            const auto reading=pulse::parse_keyboard(reply);
            battery=reading.percent; charging=reading.charging; status=reading.status;
            break;
          }
        }
      }
    }
    if(h!=INVALID_HANDLE_VALUE) CloseHandle(h);
    if(!first) std::cout << ','; first=false;
    std::string kind = mouse ? "mouse" : keyboard ? "keyboard"
      : caps.UsagePage == 1 && caps.Usage == 2 ? "mouse"
      : caps.UsagePage == 1 && caps.Usage == 6 ? "keyboard"
      : caps.UsagePage == 1 && (caps.Usage == 4 || caps.Usage == 5) ? "gamepad"
      : caps.UsagePage == 13 ? "touch" : "other";
    std::cout << "{\"vid\":" << a.VendorID << ",\"pid\":" << a.ProductID
      << ",\"deviceId\":" << quote(device_id)
      << ",\"batterySupported\":" << (mouse || keyboard ? "true" : "false")
      << ",\"transport\":" << quote(mouse || keyboard ? "2.4 ГГц" : "HID")
      << ",\"product\":" << quote(utf8(product)) << ",\"manufacturer\":" << quote(utf8(manufacturer))
      << ",\"path\":" << quote(utf8(detail->DevicePath)) << ",\"usagePage\":" << caps.UsagePage
      << ",\"usage\":" << caps.Usage << ",\"featureLength\":" << caps.FeatureReportByteLength
      << ",\"inputLength\":" << caps.InputReportByteLength << ",\"outputLength\":" << caps.OutputReportByteLength
      << ",\"kind\":" << quote(kind)
      << ",\"battery\":" << (battery<0?"null":std::to_string(battery))
      << ",\"charging\":" << (charging<0?"null":charging?"true":"false")
      << ",\"status\":" << quote(status) << ",\"raw\":" << quote(raw) << "}";
  }
  std::cout << "]\n"; SetupDiDestroyDeviceInfoList(info);
  ReleaseMutex(mutex); CloseHandle(mutex); return 0;
}
