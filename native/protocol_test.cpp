#include <cstddef>
#include "protocol.h"
#include <iostream>
#include <stdexcept>
void check(bool ok) { if(!ok) throw std::runtime_error("Protocol regression"); }
int main() {
  // Real packets from the user's receivers, captured 2026-10-03.
  std::vector<uint8_t> mouse={0x11,0xf9,0xc8,0xc7,0xe7,0xbf,0xd5,0xfa,0xfd,0xff,0xf6,0x9e,0xff,0x9d,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
  check(pulse::parse_mouse(mouse).percent==97);
  check(pulse::parse_mouse(mouse).charging==0);
  mouse[11]=0xff; check(pulse::parse_mouse(mouse).percent==0);
  mouse[11]=0xfa; check(pulse::parse_mouse(mouse).percent==5); // Never multiply a low reading by ten.
  mouse[11]=0x9a; check(pulse::parse_mouse(mouse).percent==-1);
  mouse[11]=0x9e; mouse[12]=0xfe; check(pulse::parse_mouse(mouse).charging==1);
  mouse[10]=0xff; check(pulse::parse_mouse(mouse).percent==-1);
  mouse.resize(12); check(pulse::parse_mouse(mouse).percent==-1);
  auto keyboard=pulse::keyboard_request(); keyboard[4]=95; keyboard[32]=0x80;
  check(pulse::parse_keyboard(keyboard).percent==95);
  check(pulse::parse_keyboard(keyboard).charging==-1);
  keyboard[32]=0; check(pulse::parse_keyboard(keyboard).percent==-1);
  keyboard[4]=101; keyboard[32]=134; check(pulse::parse_keyboard(keyboard).percent==-1);
  keyboard[4]=0; keyboard[32]=33; check(pulse::parse_keyboard(keyboard).percent==-1);
  keyboard[1]=0x21; check(pulse::parse_keyboard(keyboard).percent==-1);
  keyboard.resize(4); check(pulse::parse_keyboard(keyboard).percent==-1);
  check(pulse::mouse_request().size()==21 && pulse::mouse_request()[1]==0xf9);
  std::cout << "Protocol fixtures and malformed-packet checks passed\n";
}
