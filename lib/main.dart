import 'startup_setting.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'battery_service.dart';
import 'device_icons.dart';
import 'hardware_painter.dart';
import 'compact_panel.dart';
import 'widget_theme.dart';

void main(List<String> args) => runApp(
  args.contains('--widget') || args.contains('--tray')
      ? CompactApp(tray: args.contains('--tray'))
      : const PulseApp(),
);
const mint = Color(0xffb7f59b);
const lavender = Color(0xffb7b0ff);
const muted = Color(0xff90969d);
const panel = Color(0xff1a1d21);

class PulseApp extends StatelessWidget {
  const PulseApp({super.key, this.service});
  final BatteryService? service;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pulse · Заряд устройств',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xff111315),
      colorScheme: const ColorScheme.dark(
        primary: mint,
        secondary: lavender,
        surface: panel,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
      dividerColor: const Color(0xff2c3034),
      dividerTheme: const DividerThemeData(color: Color(0xff303438)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: Dashboard(service: service ?? BatteryService()),
  );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.service});
  final BatteryService service;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int page = 0;
  static const desktop = MethodChannel('pulse/desktop');
  @override
  void initState() {
    super.initState();
    widget.service.start();
  }

  @override
  void dispose() {
    widget.service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) => Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 80,
            child: Column(
              children: [
                const SizedBox(height: 30),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xff172412),
                    size: 29,
                  ),
                ),
                const SizedBox(height: 54),
                nav(Icons.space_dashboard_outlined, 'Устройства', 0),
                const SizedBox(height: 15),
                nav(Icons.tune_rounded, 'Настройки', 1),
                const Spacer(),
                nav(Icons.usb_rounded, 'Диагностика', 2),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Container(width: 1, color: const Color(0xff25282c)),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 28, 16),
                  child: Row(
                    children: [
                      const Text(
                        'pulse',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 13),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xff34383b)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'DESKTOP',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.8,
                            color: muted,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () =>
                            desktop.invokeMethod<void>('showWidget'),
                        icon: const Icon(Icons.widgets_outlined, size: 17),
                        label: const Text('Виджет'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: page == 0
                        ? devices()
                        : page == 1
                        ? settings()
                        : diagnostics(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.service.error == null
                              ? mint
                              : Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.service.busy
                            ? 'Проверяем устройства…'
                            : widget.service.autoRefresh
                            ? 'Автообновление включено'
                            : 'Автообновление на паузе',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget nav(IconData icon, String label, int index) => Tooltip(
    message: label,
    child: IconButton(
      onPressed: () => setState(() => page = index),
      style: IconButton.styleFrom(
        backgroundColor: page == index
            ? mint.withValues(alpha: .10)
            : Colors.transparent,
        foregroundColor: page == index ? mint : muted,
        minimumSize: const Size(46, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 22),
    ),
  );

  Widget devices() => SingleChildScrollView(
    key: const ValueKey('devices'),
    padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Устройства',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.tonalIcon(
              onPressed: widget.service.busy ? null : widget.service.refresh,
              icon: widget.service.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Обновить'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('add-devices'),
          onPressed: chooseDevices,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Добавить устройства'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Мои устройства',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 9),
            chip('${widget.service.devices.length}', muted),
            const Spacer(),
            Text(
              widget.service.updatedLabel,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final devices = widget.service.devices;
            if (devices.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'Устройства пока не добавлены. Нажмите «Добавить устройства» и выберите нужные из обнаруженных.',
                  style: const TextStyle(color: muted),
                ),
              );
            }
            final width = constraints.maxWidth >= 700
                ? (constraints.maxWidth - 18) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                for (final device in devices)
                  SizedBox(
                    key: ValueKey(device.id),
                    width: width,
                    child: deviceCard(
                      device,
                      device.kind == 'keyboard' ? lavender : mint,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (widget.service.error != null)
          Container(
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              color: const Color(0xff181c19),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xff2c352b)),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco_outlined, color: mint, size: 23),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Не удалось обновить данные',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.service.error!,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  void chooseDevices() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выбор устройств'),
        content: SizedBox(
          width: 500,
          height: 360,
          child: ListenableBuilder(
            listenable: widget.service,
            builder: (context, _) {
              final devices = widget.service.discoveredDevices;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pulse находит устройства автоматически. Отметьте те, которые хотите видеть в карточках и виджете.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: devices.isEmpty
                        ? Center(
                            child: Text(
                              widget.service.busy
                                  ? 'Ищем устройства…'
                                  : 'Устройства не найдены. Подключите устройство — оно появится здесь автоматически.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final device = devices[index];
                              return CheckboxListTile(
                                key: ValueKey('select-${device.id}'),
                                contentPadding: EdgeInsets.zero,
                                secondary: Icon(
                                  deviceIcon(device.kind),
                                  color: mint,
                                ),
                                title: Text(
                                  device.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  !device.connected
                                      ? 'Отключено'
                                      : device.batterySupported
                                      ? 'Чтение заряда поддерживается'
                                      : 'Заряд недоступен',
                                ),
                                value: widget.service.registry.isSelected(
                                  device.id,
                                ),
                                onChanged: (value) =>
                                    widget.service.setDeviceSelected(
                                      device.id,
                                      value ?? false,
                                    ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Widget deviceCard(DeviceState device, Color accent) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(panel, accent, .035)!, panel],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xff303438)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(deviceIcon(device.kind), color: accent, size: 19),
            const SizedBox(width: 8),
            Text(
              deviceCategory(device.kind),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                color: muted,
              ),
            ),
            const Spacer(),
            chip(
              device.connected ? device.transport : 'Отключено',
              device.connected ? accent : muted,
            ),
          ],
        ),
        SizedBox(
          height: 148,
          child: Center(
            child: device.kind == 'mouse' || device.kind == 'keyboard'
                ? CustomPaint(
                    size: Size(device.kind == 'mouse' ? 130 : 255, 122),
                    painter: HardwarePainter(device.kind == 'mouse', accent),
                  )
                : Icon(deviceIcon(device.kind), size: 80, color: accent),
          ),
        ),
        Text(
          device.manufacturer.isEmpty ? 'HID' : device.manufacturer,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent,
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          device.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              device.battery == null ? '—' : '${device.battery}',
              style: TextStyle(
                fontSize: 54,
                height: 1,
                fontWeight: FontWeight.w300,
                color: device.battery != null && device.battery! <= 20
                    ? const Color(0xffffbc7d)
                    : Colors.white,
                letterSpacing: -2,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                device.battery == null ? '' : '%',
                style: const TextStyle(fontSize: 22, color: muted),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Icon(
                device.charging
                    ? Icons.bolt_rounded
                    : Icons.battery_5_bar_rounded,
                color: accent,
                size: 24,
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        TweenAnimationBuilder<double>(
          tween: Tween(end: (device.battery ?? 0) / 100),
          duration: const Duration(milliseconds: 650),
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              color: device.battery != null && device.battery! <= 20
                  ? Colors.orangeAccent
                  : accent,
              backgroundColor: const Color(0xff34383b),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: device.fresh ? accent : muted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device.label,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
        if (!device.fresh) ...[
          const SizedBox(height: 15),
          const Divider(height: 1),
          const SizedBox(height: 13),
          Text(
            device.detail,
            style: const TextStyle(fontSize: 11, height: 1.5, color: muted),
          ),
        ],
      ],
    ),
  );

  Widget chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
    ),
  );

  Widget settings() => ListView(
    key: const ValueKey('settings'),
    padding: const EdgeInsets.all(32),
    children: [
      const StartupSetting(),
      const SizedBox(height: 20),
      const Text(
        'Настройки',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Тема виджета',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            WidgetThemePicker(
              selected: widget.service.widgetTheme,
              onChanged: widget.service.setWidgetTheme,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      settingTile(
        Icons.sync_rounded,
        'Автоматическое обновление',
        'Проверка заряда по таймеру. Подключения обнаруживаются всегда.',
        Switch(
          value: widget.service.autoRefresh,
          onChanged: widget.service.setAutoRefresh,
        ),
      ),
      settingTile(
        Icons.timer_outlined,
        'Интервал проверки',
        'Частый опрос может мешать переходу устройств в сон',
        DropdownButton<int>(
          value: widget.service.interval,
          underline: const SizedBox(),
          items: [30, 60, 120, 300]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v сек.')))
              .toList(),
          onChanged: (v) {
            if (v != null) widget.service.setInterval(v);
          },
        ),
      ),
      settingTile(
        Icons.notifications_none_rounded,
        'Низкий заряд',
        'Уведомление Windows при заряде 20% и ниже',
        Switch(
          value: widget.service.notifications,
          onChanged: widget.service.setNotifications,
        ),
      ),
      settingTile(
        Icons.picture_in_picture_alt_rounded,
        'Работа в трее',
        'Опрос продолжится. Открыть — через значок Pulse.',
        OutlinedButton(
          onPressed: () async {
            try {
              await desktop.invokeMethod<void>('hideToTray');
            } on MissingPluginException {
              /* Tests. */
            }
          },
          child: const Text('Свернуть'),
        ),
      ),
      settingTile(
        Icons.widgets_outlined,
        'Виджет на рабочем столе',
        'Положение и закрепление сохраняются',
        OutlinedButton(
          onPressed: () => desktop.invokeMethod<void>('showWidget'),
          child: const Text('Показать'),
        ),
      ),
      const SizedBox(height: 25),
      const Text('Pulse 1.1.0', style: TextStyle(color: mint)),
    ],
  );
  Widget settingTile(
    IconData icon,
    String title,
    String subtitle,
    Widget control,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(icon, color: mint),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        control,
      ],
    ),
  );

  Widget diagnostics() => ListView(
    key: const ValueKey('diagnostics'),
    padding: const EdgeInsets.all(32),
    children: [
      const Text(
        'Подключение устройств',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Если заряд не появился: разбудите устройство, проверьте режим 2.4 ГГц\nи закройте фирменную программу, которая может занимать ресивер.',
        style: TextStyle(color: muted, height: 1.7),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          FilledButton.icon(
            onPressed: widget.service.busy ? null : widget.service.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить проверку'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: const JsonEncoder.withIndent(
                    '  ',
                  ).convert(widget.service.diagnostics),
                ),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Диагностика скопирована')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 17),
            label: const Text('Скопировать отчёт'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      ...widget.service.diagnostics.map(
        (d) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SelectableText(
            '${d['product']}\nVID ${(d['vid'] as int).toRadixString(16)} · PID ${(d['pid'] as int).toRadixString(16)} · Usage ${(d['usagePage'] as int).toRadixString(16)}\n${d['status']}\n${d['raw']}',
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              height: 1.7,
            ),
          ),
        ),
      ),
      if (widget.service.diagnostics.isEmpty)
        const Text(
          'Ресиверы пока не обнаружены.',
          style: TextStyle(color: muted),
        ),
    ],
  );
}
