import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widget_theme.dart';
import 'device_icons.dart';

class CompactApp extends StatefulWidget {
  const CompactApp({
    super.key,
    this.tray = false,
    this.initialSnapshot,
    this.initialTheme = 0,
  });
  final bool tray;
  final Map<String, dynamic>? initialSnapshot;
  final int initialTheme;
  @override
  State<CompactApp> createState() => _CompactAppState();
}

class _CompactAppState extends State<CompactApp> {
  static const _channel = MethodChannel('pulse/desktop');
  Map<String, dynamic> snapshot = {};
  bool pinned = false, choosingTheme = false;
  int themeId = 0;
  WidgetPalette get palette => WidgetPalette.fromId(themeId);
  List<Map<String, dynamic>> get devices => (snapshot['devices'] as List? ?? [])
      .map((d) => Map<String, dynamic>.from(d as Map))
      .toList();

  @override
  void initState() {
    super.initState();
    snapshot = widget.initialSnapshot ?? {};
    themeId = widget.initialTheme;
    if (widget.initialSnapshot == null) {
      _channel.setMethodCallHandler((call) async {
        if (!mounted) return;
        if (call.method == 'snapshot') {
          setState(
            () => snapshot = Map<String, dynamic>.from(call.arguments as Map),
          );
        } else if (call.method == 'widgetThemeChanged') {
          setState(() => themeId = call.arguments as int);
        }
      });
      _load();
    }
  }

  Future<void> _load() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('getSnapshot');
    final pin = await _channel.invokeMethod<bool>('getPinned');
    final theme = await _channel.invokeMethod<int>('getWidgetTheme');
    if (mounted) {
      setState(() {
        snapshot = data ?? {};
        pinned = pin ?? false;
        themeId = theme ?? 0;
      });
    }
  }

  Future<void> _selectTheme(int id) async {
    if (widget.initialSnapshot == null) {
      await _channel.invokeMethod<void>('setWidgetTheme', id);
    }
    if (mounted) {
      setState(() {
        themeId = id;
        choosingTheme = false;
      });
    }
  }

  Future<void> _act(String method) async {
    if (widget.initialSnapshot != null) return;
    if (method == 'togglePin') {
      final pin = await _channel.invokeMethod<bool>(method);
      if (mounted) setState(() => pinned = pin ?? false);
    } else {
      await _channel.invokeMethod<void>(method);
    }
  }

  @override
  void dispose() {
    if (widget.initialSnapshot == null) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      colorScheme: ColorScheme.dark(
        primary: palette.mouse,
        surface: palette.background,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 450),
      ),
    ),
    home: Scaffold(
      backgroundColor: palette.background,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.end, palette.background],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: palette.muted.withValues(alpha: .32),
            width: .7,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CustomPaint(
            painter: ForestBackdrop(palette),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: choosingTheme ? _themes() : _readings(),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _themes() => Column(
    key: const ValueKey('theme-picker'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _icon(
            Icons.arrow_back_rounded,
            'Назад',
            () => setState(() => choosingTheme = false),
          ),
          const SizedBox(width: 6),
          Text(
            'Тема виджета',
            style: TextStyle(
              color: palette.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      WidgetThemePicker(
        selected: themeId,
        compact: true,
        onChanged: _selectTheme,
      ),
    ],
  );

  Widget _readings() => Column(
    key: const ValueKey('readings'),
    children: [
      Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.tray ? null : (_) => _act('drag'),
              child: SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Icon(
                      palette.forest
                          ? Icons.nights_stay_outlined
                          : Icons.bolt_rounded,
                      color: palette.mouse,
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'pulse',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(width: 9),
                    if (!widget.tray)
                      Icon(
                        Icons.drag_indicator_rounded,
                        color: palette.muted.withValues(alpha: .4),
                        size: 13,
                      ),
                  ],
                ),
              ),
            ),
          ),
          _icon(
            Icons.palette_outlined,
            'Тема виджета',
            () => setState(() => choosingTheme = true),
          ),
          if (!widget.tray)
            _icon(
              pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              pinned ? 'Открепить от переднего плана' : 'Поверх окон',
              () => _act('togglePin'),
              active: pinned,
            ),
          _icon(Icons.close_rounded, 'Скрыть', () => _act('hide')),
        ],
      ),
      const SizedBox(height: 14),
      Expanded(
        child: devices.isEmpty
            ? Center(
                child: Text(
                  snapshot['busy'] == true
                      ? 'Ищем устройства…'
                      : 'Добавьте устройства в Pulse',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: devices.length,
                itemBuilder: (context, index) => _device(devices[index]),
                separatorBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Divider(
                    height: 1,
                    color: palette.muted.withValues(alpha: .16),
                  ),
                ),
              ),
      ),
      Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: palette.mouse.withValues(alpha: .7),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              snapshot['busy'] == true
                  ? 'Обновление…'
                  : snapshot['updated'] as String? ?? 'Ожидание данных',
              style: TextStyle(color: palette.muted, fontSize: 9),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _icon(
            Icons.refresh_rounded,
            'Обновить',
            snapshot['busy'] == true ? null : () => _act('refresh'),
          ),
          if (widget.tray)
            _icon(
              Icons.widgets_outlined,
              'Виджет на рабочем столе',
              () => _act('showWidget'),
            ),
          _icon(
            Icons.open_in_new_rounded,
            'Открыть Pulse',
            () => _act('openMain'),
          ),
        ],
      ),
    ],
  );

  Widget _icon(
    IconData icon,
    String tooltip,
    VoidCallback? action, {
    bool active = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: action,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 29, height: 30),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 14, color: active ? palette.mouse : palette.muted),
  );

  Widget _device(Map<String, dynamic> data) {
    final kind = data['kind'] as String? ?? 'other';
    final icon = deviceIcon(kind);
    final accent = kind == 'keyboard' ? palette.keyboard : palette.mouse;
    final value = data['battery'] as int?;
    final fresh = data['fresh'] == true;
    final color = value != null && value <= 20
        ? const Color(0xffffaa7b)
        : accent;
    return Row(
      key: ValueKey(data['id']),
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (value ?? 0) / 100,
                  strokeWidth: 2,
                  strokeCap: StrokeCap.round,
                  backgroundColor: accent.withValues(alpha: .11),
                  color: color.withValues(alpha: fresh ? .8 : .25),
                ),
              ),
              Icon(icon, color: accent, size: 23),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (data['manufacturer'] as String? ?? '').isEmpty
                    ? deviceCategory(kind)
                    : data['manufacturer'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 8,
                  letterSpacing: 1.7,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data['name'] as String? ?? 'HID-устройство',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                data['status'] as String? ?? 'Поиск…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: fresh ? palette.muted : const Color(0xffd2b78d),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value == null ? '—' : '$value%',
              style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w300,
                letterSpacing: -.8,
                color: fresh ? color : palette.muted,
              ),
            ),
            if (data['charging'] == true)
              Icon(Icons.bolt_rounded, size: 12, color: color)
            else if (!fresh && value != null)
              Text(
                'ранее',
                style: TextStyle(fontSize: 9, color: palette.muted),
              ),
          ],
        ),
      ],
    );
  }
}
