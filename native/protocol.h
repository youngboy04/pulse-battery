#pragma once
#include <cstddef>
#include <vector>
#include <cstdint>
namespace pulse {
struct Reading { int percent=-1; int charging=-1; const char* status="invalid_response"; };
inline std::vector<uint8_t> mouse_request() {
  std::vector<uint8_t> b(21,0xff); b[0]=0x11; b[1]=0xf9; return b;
}
inline std::vector<uint8_t> keyboard_request() {
  std::vector<uint8_t> b(33,0); b[1]=0x20; b[2]=1; b[32]=0x21; return b;
}
inline Reading parse_mouse(const std::vector<uint8_t>& b) {
  if(b.size()!=21 || b[0]!=0x11 || b[1]!=0xf9) return {};
  const int vid=(b[2]^255)|((b[3]^255)<<8);
  if(vid==0 || !((b[10]^255)&8)) return {-1,-1,"asleep"};
  if(vid!=0x3837 && vid!=0x5253) return {};
  const int level=b[11]^255, charge=b[12]^255;
  if(level>100 || charge>2) return {};
  return {level,charge==1?1:0,"ok"};
}
inline Reading parse_keyboard(const std::vector<uint8_t>& b) {
  if(b.size()!=33 || b[0]!=0 || b[1]!=0x20 || b[2]!=1 || b[3]!=0) return {};
  unsigned sum=0; for(size_t i=0;i<32;i++) sum+=b[i];
  if((sum&255)!=b[32] || b[4]>100) return {};
  // The manufacturer's UI ignores 0: it may be a sleeping radio, not an empty cell.
  if(b[4]==0) return {-1,-1,"asleep"};
  return {b[4],-1,"ok"};
}
}
