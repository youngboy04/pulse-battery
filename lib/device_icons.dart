import 'package:flutter/material.dart';

IconData deviceIcon(String kind) => switch (kind) {
  'mouse' => Icons.mouse_outlined,
  'keyboard' => Icons.keyboard_outlined,
  'gamepad' => Icons.sports_esports_outlined,
  'touch' => Icons.touch_app_outlined,
  _ => Icons.usb_rounded,
};

String deviceCategory(String kind) => switch (kind) {
  'mouse' => 'МЫШЬ',
  'keyboard' => 'КЛАВИАТУРА',
  'gamepad' => 'ГЕЙМПАД',
  'touch' => 'СЕНСОР',
  _ => 'УСТРОЙСТВО',
};
