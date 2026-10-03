// Run the actual Windows UI and hardware service, then export its Flutter frames.
// No fixtures or fabricated battery readings; user preferences are only read.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pulse_battery/battery_service.dart';
import 'package:pulse_battery/compact_panel.dart';
import 'package:pulse_battery/main.dart';

class CaptureService extends BatteryService {
  final ready = Completer<void>();
  @override
  Future<void> start() async {
    await super.start();
    ready.complete();
  }
}

Future<void> main(List<String> args) async {
  // The Windows runner starts the same entry point for secondary engines.
  // Only the main window exports files; secondary windows keep their normal UI.
  if (args.contains('--widget') || args.contains('--tray')) {
    runApp(CompactApp(tray: args.contains('--tray')));
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final output = Directory('docs/screenshots');
  await output.create(recursive: true);
  final frame = GlobalKey();
  final service = CaptureService();
  runApp(
    RepaintBoundary(
      key: frame,
      child: PulseApp(service: service),
    ),
  );

  Future<void> capture(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  await service.ready.future;
  if (service.error != null) throw StateError(service.error!);
  await capture('dashboard');
  void openPicker(Element element) {
    final widget = element.widget;
    if (widget is OutlinedButton &&
        widget.key == const ValueKey('add-devices')) {
      widget.onPressed!();
      return;
    }
    element.visitChildren(openPicker);
  }

  (frame.currentContext! as Element).visitChildren(openPicker);
  await capture('device-picker');
  final snapshot = {
    'devices': service.devices.map((d) => d.toSnapshot()).toList(),
    'busy': false,
    'updated': service.updatedLabel,
  };
  final theme = service.widgetTheme;
  runApp(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 360,
        height: 282,
        child: RepaintBoundary(
          key: frame,
          child: CompactApp(initialSnapshot: snapshot, initialTheme: theme),
        ),
      ),
    ),
  );
  await capture('widget');
  exit(0);
}
