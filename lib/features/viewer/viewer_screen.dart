import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'measurements.dart';

class ViewerResult {
  final Uint8List editedPng;
  final Uint8List annotatedPng;
  final Map<String, dynamic> session;
  const ViewerResult({
    required this.editedPng,
    required this.annotatedPng,
    required this.session,
  });
}

/// An offline viewer. All marks are normalized to the transformed raster, not
/// screen coordinates. Zoom and pan never alter measurement geometry.
class ViewerScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final Uint8List? comparisonBytes;
  final double? pixelSpacingMm;
  final Map<String, dynamic>? initialSession;
  final bool english;
  const ViewerScreen({
    super.key,
    required this.imageBytes,
    this.comparisonBytes,
    this.pixelSpacingMm,
    this.initialSession,
    this.english = false,
  });
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

enum _Tool { pan, freehand, line, arrow, circle, distance, angle, axis }

class _Mark {
  final _Tool tool;
  final List<Offset> points;
  _Mark(this.tool, this.points);
  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
  };
  static _Mark? fromJson(dynamic value) {
    if (value is! Map) return null;
    final t = _Tool.values.where((t) => t.name == value['tool']).firstOrNull;
    if (t == null || t == _Tool.pan || value['points'] is! List) return null;
    final points = <Offset>[];
    for (final p in value['points'] as List) {
      if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) {
        return null;
      }
      final x = (p[0] as num).toDouble();
      final y = (p[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
        return null;
      }
      points.add(Offset(x, y));
    }
    final minimum = t == _Tool.angle ? 3 : 2;
    return points.length >= minimum ? _Mark(t, points) : null;
  }
}

class _ViewerScreenState extends State<ViewerScreen> {
  final TransformationController _transform = TransformationController();
  img.Image? _original;
  img.Image? _raster;
  Uint8List? _display;
  String? _error;
  bool _busy = true;
  bool _showMarks = true;
  bool _compare = false;
  bool _invert = false;
  double _brightness = 1;
  double _contrast = 1;
  double? _mmPerPixel;
  String? _calibrationSource;
  _Tool _tool = _Tool.pan;
  List<Map<String, dynamic>> _operations = [];
  List<_Mark> _marks = [];
  final List<_Mark> _redo = [];
  _Mark? _draft;
  String tr(String vi, String en) => widget.english ? en : vi;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Future<void>.delayed(Duration.zero);
      final source = img.decodeImage(widget.imageBytes);
      if (source == null) throw const FormatException('Unsupported image');
      _original = img.bakeOrientation(source);
      final s = widget.initialSession;
      if (s != null) {
        _brightness = ((s['brightness'] as num?)?.toDouble() ?? 1).clamp(
          .25,
          2,
        );
        _contrast = ((s['contrast'] as num?)?.toDouble() ?? 1).clamp(.25, 2.5);
        _invert = s['invert'] == true;
        _showMarks = s['showMarks'] != false;
        _operations = (s['operations'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _marks = (s['marks'] as List? ?? [])
            .map(_Mark.fromJson)
            .whereType<_Mark>()
            .toList();
        final calibration = s['calibration'];
        if (calibration is Map && calibration['confirmed'] == true) {
          final value = (calibration['mmPerPixel'] as num?)?.toDouble();
          if (value != null && value.isFinite && value > 0) {
            _mmPerPixel = value;
            _calibrationSource = calibration['source'] as String?;
          }
        }
      }
      _rebuild();
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr(
            'Không thể mở ảnh đã chọn.',
            'The selected image could not be opened.',
          );
        });
      }
    }
  }

  void _rebuild() {
    var raster = img.Image.from(_original!);
    for (final op in _operations) {
      if (op['type'] == 'rotate') {
        raster = img.copyRotate(raster, angle: 90);
      } else if (op['type'] == 'crop') {
        final x = (((op['x'] as num).toDouble()) * raster.width).round().clamp(
          0,
          raster.width - 1,
        );
        final y = (((op['y'] as num).toDouble()) * raster.height).round().clamp(
          0,
          raster.height - 1,
        );
        final w = (((op['w'] as num).toDouble()) * raster.width).round().clamp(
          1,
          raster.width - x,
        );
        final h = (((op['h'] as num).toDouble()) * raster.height).round().clamp(
          1,
          raster.height - y,
        );
        raster = img.copyCrop(raster, x: x, y: y, width: w, height: h);
      }
    }
    _raster = raster;
    _updateDisplay();
  }

  void _updateDisplay() {
    var adjusted = img.adjustColor(
      img.Image.from(_raster!),
      brightness: _brightness,
      contrast: _contrast,
    );
    if (_invert) adjusted = img.invert(adjusted);
    _display = Uint8List.fromList(img.encodePng(adjusted));
  }

  void _rotate() {
    setState(() {
      _operations.add({'type': 'rotate'});
      _marks = _marks
          .map(
            (m) => _Mark(
              m.tool,
              m.points.map((p) => Offset(1 - p.dy, p.dx)).toList(),
            ),
          )
          .toList();
      _redo.clear();
      _draft = null;
      _rebuild();
      _transform.value = Matrix4.identity();
    });
  }

  void _finishMark(_Mark mark) {
    final a = mark.points.first;
    final b = mark.points.last;
    if (mark.tool == _Tool.freehand) {
      if (!mark.points.any((p) => (p - a).distance >= .002)) return;
    } else if (mark.tool != _Tool.angle && (a - b).distance < .002) {
      return;
    }
    setState(() {
      _marks.add(mark);
      _redo.clear();
      _draft = null;
    });
  }

  Offset _point(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0, 1),
    (local.dy / size.height).clamp(0, 1),
  );

  void _start(DragStartDetails d, Size size) {
    if (_tool == _Tool.pan || _tool == _Tool.angle) return;
    final p = _point(d.localPosition, size);
    setState(() => _draft = _Mark(_tool, [p, p]));
  }

  void _move(DragUpdateDetails d, Size size) {
    if (_draft == null || _tool == _Tool.angle) return;
    final p = _point(d.localPosition, size);
    setState(() {
      if (_tool == _Tool.freehand) {
        _draft!.points.add(p);
      } else {
        _draft!.points[1] = p;
      }
    });
  }

  void _end(DragEndDetails d) {
    final draft = _draft;
    if (draft != null && _tool != _Tool.angle) _finishMark(draft);
    setState(() => _draft = null);
  }

  void _tap(TapDownDetails d, Size size) {
    if (_tool != _Tool.angle) return;
    final p = _point(d.localPosition, size);
    setState(() {
      _draft ??= _Mark(_Tool.angle, []);
      _draft!.points.add(p);
    });
    if (_draft!.points.length == 3) _finishMark(_draft!);
  }

  Future<void> _crop() async {
    var horizontal = const RangeValues(0, 1);
    var vertical = const RangeValues(0, 1);
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(tr('Cắt ảnh', 'Crop image')),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: _raster!.width / _raster!.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_display!, fit: BoxFit.fill),
                        CustomPaint(
                          painter: _CropPainter(
                            Rect.fromLTRB(
                              horizontal.start,
                              vertical.start,
                              horizontal.end,
                              vertical.end,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(tr('Giới hạn ngang', 'Horizontal bounds')),
                  RangeSlider(
                    values: horizontal,
                    onChanged: (v) {
                      if (v.end - v.start >= .1) update(() => horizontal = v);
                    },
                  ),
                  Text(tr('Giới hạn dọc', 'Vertical bounds')),
                  RangeSlider(
                    values: vertical,
                    onChanged: (v) {
                      if (v.end - v.start >= .1) update(() => vertical = v);
                    },
                  ),
                  if (_marks.isNotEmpty)
                    Text(
                      tr(
                        'Cắt ảnh sẽ xóa chú thích hiện tại. Ảnh gốc được giữ nguyên.',
                        'Cropping clears current annotations. The original image is preserved.',
                      ),
                      style: const TextStyle(color: Colors.orange),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Hủy', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Áp dụng', 'Apply')),
            ),
          ],
        ),
      ),
    );
    if (apply != true || !mounted) return;
    setState(() {
      _operations.add({
        'type': 'crop',
        'x': horizontal.start,
        'y': vertical.start,
        'w': horizontal.end - horizontal.start,
        'h': vertical.end - vertical.start,
      });
      _marks.clear();
      _redo.clear();
      _draft = null;
      _rebuild();
      _transform.value = Matrix4.identity();
    });
  }

  Future<void> _adjust() async {
    var brightness = _brightness;
    var contrast = _contrast;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Độ sáng / tương phản', 'Brightness / contrast'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(tr('Độ sáng', 'Brightness')),
                Slider(
                  value: brightness,
                  min: .25,
                  max: 2,
                  label: brightness.toStringAsFixed(2),
                  onChanged: (v) => update(() => brightness = v),
                ),
                Text(tr('Tương phản', 'Contrast')),
                Slider(
                  value: contrast,
                  min: .25,
                  max: 2.5,
                  label: contrast.toStringAsFixed(2),
                  onChanged: (v) => update(() => contrast = v),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr('Áp dụng', 'Apply')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (apply == true && mounted) {
      setState(() {
        _brightness = brightness;
        _contrast = contrast;
        _updateDisplay();
      });
    }
  }

  Future<void> _calibrate() async {
    final last = _marks.where((m) => m.tool == _Tool.distance).lastOrNull;
    final px = last == null
        ? null
        : distancePixels(
            _toPixel(last.points.first),
            _toPixel(last.points.last),
          );
    final controller = TextEditingController();
    var error = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(tr('Hiệu chuẩn phép đo', 'Measurement calibration')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Chỉ dùng mm khi có thước chuẩn cùng mặt phẳng hoặc đã xác minh Pixel Spacing. Ảnh chụp phim có thể bị méo phối cảnh.',
                    'Use mm only with a same-plane reference or verified Pixel Spacing. Photographs may have perspective distortion.',
                  ),
                ),
                if (_mmPerPixel != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${_mmPerPixel!.toStringAsFixed(5)} mm/px · ${_calibrationSource ?? ''}',
                    ),
                  ),
                if (px != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      'Đường đo gần nhất: ${px.toStringAsFixed(1)} px',
                      'Last distance line: ${px.toStringAsFixed(1)} px',
                    ),
                  ),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr(
                        'Chiều dài thực đã xác minh (mm)',
                        'Verified real length (mm)',
                      ),
                    ),
                  ),
                ] else
                  Text(
                    tr(
                      'Vẽ một đường Đo khoảng cách trên thước chuẩn trước khi hiệu chuẩn thủ công.',
                      'First draw a Distance line along the known reference.',
                    ),
                  ),
                if (widget.pixelSpacingMm != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      tr(
                        'DICOM: ${widget.pixelSpacingMm} mm/px. Chưa xác minh hình học.',
                        'DICOM: ${widget.pixelSpacingMm} mm/px. Geometry is unverified.',
                      ),
                    ),
                  ),
                if (error.isNotEmpty)
                  Text(error, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'clear'),
              child: Text(tr('Dùng pixel', 'Use pixels')),
            ),
            if (widget.pixelSpacingMm != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 'dicom'),
                child: Text(tr('Tôi đã xác minh DICOM', 'I verified DICOM')),
              ),
            if (px != null)
              FilledButton(
                onPressed: () {
                  final length = double.tryParse(
                    controller.text.replaceAll(',', '.'),
                  );
                  if (length == null ||
                      !length.isFinite ||
                      length <= 0 ||
                      px <= 0) {
                    update(
                      () => error = tr(
                        'Nhập độ dài hợp lệ.',
                        'Enter a valid length.',
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, 'manual:$length');
                },
                child: Text(tr('Xác nhận thước chuẩn', 'Confirm reference')),
              ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result == 'clear') {
        _mmPerPixel = null;
        _calibrationSource = null;
      }
      if (result == 'dicom' &&
          widget.pixelSpacingMm != null &&
          widget.pixelSpacingMm! > 0) {
        _mmPerPixel = widget.pixelSpacingMm;
        _calibrationSource = 'dicom_user_confirmed';
      }
      if (result.startsWith('manual:') && px != null) {
        _mmPerPixel = double.parse(result.substring(7)) / px;
        _calibrationSource = 'manual_known_distance';
      }
    });
    // The dialog route releases its TextField after the closing animation.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  }

  Offset _toPixel(Offset p) =>
      Offset(p.dx * _raster!.width, p.dy * _raster!.height);

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Khôi phục ảnh gốc?', 'Restore original image?')),
        content: Text(
          tr(
            'Các điều chỉnh, hiệu chuẩn và chú thích trong trình xem sẽ bị xóa.',
            'Viewer adjustments, calibration, and annotations will be cleared.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Khôi phục', 'Restore')),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      setState(() {
        _operations.clear();
        _marks.clear();
        _redo.clear();
        _draft = null;
        _brightness = 1;
        _contrast = 1;
        _invert = false;
        _mmPerPixel = null;
        _calibrationSource = null;
        _rebuild();
        _transform.value = Matrix4.identity();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bytes = _display!;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final source = frame.image;
      final scale = math.min(1.0, 2560 / math.max(source.width, source.height));
      final size = Size(
        (source.width * scale).roundToDouble(),
        (source.height * scale).roundToDouble(),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
      if (_showMarks) {
        _MarkPainter(
          marks: _marks,
          pixelSize: Size(
            _raster!.width.toDouble(),
            _raster!.height.toDouble(),
          ),
          mmPerPixel: _mmPerPixel,
        ).paint(canvas, size);
      }
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final encoded = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final annotated = encoded!.buffer.asUint8List();
      source.dispose();
      codec.dispose();
      rendered.dispose();
      picture.dispose();
      if (!mounted) return;
      Navigator.pop(
        context,
        ViewerResult(
          editedPng: bytes,
          annotatedPng: annotated,
          session: {
            'version': 1,
            'operations': _operations,
            'brightness': _brightness,
            'contrast': _contrast,
            'invert': _invert,
            'showMarks': _showMarks,
            'marks': _marks.map((m) => m.toJson()).toList(),
            if (_mmPerPixel != null)
              'calibration': {
                'mmPerPixel': _mmPerPixel,
                'source': _calibrationSource,
                'confirmed': true,
              },
          },
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Không thể lưu ảnh chú thích.',
                'Could not save the annotated image.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  String _toolName(_Tool tool) => switch (tool) {
    _Tool.pan => tr('Di chuyển / phóng to', 'Pan / zoom'),
    _Tool.freehand => tr('Vẽ tự do', 'Freehand'),
    _Tool.line => tr('Đường thẳng', 'Line'),
    _Tool.arrow => tr('Mũi tên', 'Arrow'),
    _Tool.circle => tr('Vòng tròn', 'Circle'),
    _Tool.distance => tr('Đo khoảng cách', 'Distance'),
    _Tool.angle => tr('Đo góc · chạm 3 điểm', 'Angle · tap 3 points'),
    _Tool.axis => tr('Trục / tham chiếu khớp', 'Axis / joint reference'),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff080f18),
    appBar: AppBar(
      title: Text(tr('Xem và đo X-quang', 'Radiograph viewer')),
      actions: [
        IconButton(
          tooltip: tr('Vừa màn hình', 'Fit to screen'),
          onPressed: _busy
              ? null
              : () => setState(() => _transform.value = Matrix4.identity()),
          icon: const Icon(Icons.fit_screen),
        ),
        if (widget.comparisonBytes != null)
          IconButton(
            tooltip: tr('So sánh AP / nghiêng', 'Compare AP / lateral'),
            onPressed: () => setState(() => _compare = !_compare),
            icon: Icon(
              _compare
                  ? Icons.view_agenda_outlined
                  : Icons.view_column_outlined,
            ),
          ),
        IconButton(
          tooltip: tr('Lưu ảnh và chú thích', 'Save image and annotations'),
          onPressed: _busy || _error != null ? null : _save,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          )
        : SafeArea(
            child: Column(
              children: [
                Container(
                  color: const Color(0xff14202e),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    _mmPerPixel == null
                        ? tr(
                            'Đơn vị: pixel · Chưa hiệu chuẩn mm',
                            'Units: pixels · mm not calibrated',
                          )
                        : tr(
                            'Đơn vị: mm · Bác sĩ đã xác nhận hiệu chuẩn',
                            'Units: mm · Clinician-confirmed calibration',
                          ),
                    style: const TextStyle(
                      color: Color(0xffb9d6eb),
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final ratio = _raster!.width / _raster!.height;
                            var width = constraints.maxWidth;
                            var height = width / ratio;
                            if (height > constraints.maxHeight) {
                              height = constraints.maxHeight;
                              width = height * ratio;
                            }
                            final size = Size(width, height);
                            return Center(
                              child: InteractiveViewer(
                                transformationController: _transform,
                                minScale: .5,
                                maxScale: 8,
                                panEnabled: _tool == _Tool.pan,
                                scaleEnabled: _tool == _Tool.pan,
                                boundaryMargin: const EdgeInsets.all(120),
                                child: SizedBox(
                                  width: width,
                                  height: height,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart:
                                        _tool == _Tool.pan ||
                                            _tool == _Tool.angle
                                        ? null
                                        : (d) => _start(d, size),
                                    onPanUpdate:
                                        _tool == _Tool.pan ||
                                            _tool == _Tool.angle
                                        ? null
                                        : (d) => _move(d, size),
                                    onPanEnd:
                                        _tool == _Tool.pan ||
                                            _tool == _Tool.angle
                                        ? null
                                        : _end,
                                    onTapDown: _tool == _Tool.angle
                                        ? (d) => _tap(d, size)
                                        : null,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.memory(
                                          _display!,
                                          fit: BoxFit.fill,
                                          gaplessPlayback: true,
                                        ),
                                        if (_showMarks)
                                          CustomPaint(
                                            painter: _MarkPainter(
                                              marks: [..._marks, ?_draft],
                                              pixelSize: Size(
                                                _raster!.width.toDouble(),
                                                _raster!.height.toDouble(),
                                              ),
                                              mmPerPixel: _mmPerPixel,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (_compare && widget.comparisonBytes != null)
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.white24),
                              ),
                            ),
                            child: InteractiveViewer(
                              minScale: .5,
                              maxScale: 8,
                              child: Image.memory(
                                widget.comparisonBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_tool == _Tool.angle)
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      tr(
                        'Chạm điểm đầu → đỉnh góc → điểm cuối. Đổi công cụ để hủy.',
                        'Tap first point → vertex → last point. Change tools to cancel.',
                      ),
                      style: const TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                Container(
                  color: const Color(0xff14202e),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<_Tool>(
                            value: _tool,
                            isExpanded: true,
                            dropdownColor: const Color(0xff14202e),
                            style: const TextStyle(color: Colors.white),
                            items: _Tool.values
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(_toolName(t)),
                                  ),
                                )
                                .toList(),
                            onChanged: (t) => setState(() {
                              _tool = t!;
                              if (_tool != _Tool.pan) _showMarks = true;
                              _draft = null;
                            }),
                          ),
                        ),
                      ),
                      IconButton(
                        color: Colors.white,
                        tooltip: tr('Hoàn tác chú thích', 'Undo annotation'),
                        onPressed: _marks.isEmpty
                            ? null
                            : () => setState(
                                () => _redo.add(_marks.removeLast()),
                              ),
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        color: Colors.white,
                        tooltip: tr('Làm lại chú thích', 'Redo annotation'),
                        onPressed: _redo.isEmpty
                            ? null
                            : () => setState(
                                () => _marks.add(_redo.removeLast()),
                              ),
                        icon: const Icon(Icons.redo),
                      ),
                      IconButton(
                        color: Colors.white,
                        tooltip: tr(
                          'Ẩn / hiện chú thích',
                          'Show / hide annotations',
                        ),
                        onPressed: () =>
                            setState(() => _showMarks = !_showMarks),
                        icon: Icon(
                          _showMarks ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xff14202e),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _action(
                          Icons.rotate_right,
                          tr('Xoay', 'Rotate'),
                          _rotate,
                        ),
                        _action(Icons.crop, tr('Cắt', 'Crop'), _crop),
                        _action(
                          Icons.tonality,
                          tr('Đảo màu', 'Invert'),
                          () => setState(() {
                            _invert = !_invert;
                            _updateDisplay();
                          }),
                        ),
                        _action(
                          Icons.tune,
                          tr('Điều chỉnh', 'Adjust'),
                          _adjust,
                        ),
                        _action(
                          Icons.straighten,
                          tr('Hiệu chuẩn', 'Calibrate'),
                          _calibrate,
                        ),
                        _action(
                          Icons.restart_alt,
                          tr('Khôi phục', 'Reset'),
                          _reset,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
  Widget _action(IconData icon, String label, VoidCallback action) =>
      TextButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      );
}

class _MarkPainter extends CustomPainter {
  final List<_Mark> marks;
  final Size pixelSize;
  final double? mmPerPixel;
  _MarkPainter({required this.marks, required this.pixelSize, this.mmPerPixel});
  @override
  void paint(Canvas canvas, Size size) {
    final lineWidth = math.max(1.4, math.min(size.width, size.height) / 250);
    final paint = Paint()
      ..color = const Color(0xff48e6de)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    Offset px(Offset p) =>
        Offset(p.dx * pixelSize.width, p.dy * pixelSize.height);
    for (final m in marks) {
      if (m.points.isEmpty) continue;
      final points = m.points.map(at).toList();
      final first = points.first;
      final last = points.last;
      if (m.tool == _Tool.circle) {
        canvas.drawOval(Rect.fromPoints(first, last), paint);
      } else if (m.tool == _Tool.freehand) {
        final path = Path()..moveTo(first.dx, first.dy);
        for (final p in points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      } else if (m.tool == _Tool.angle) {
        for (var i = 1; i < points.length; i++) {
          canvas.drawLine(points[i - 1], points[i], paint);
        }
        for (final p in points) {
          canvas.drawCircle(p, lineWidth * 2, paint);
        }
        if (points.length == 3) {
          final degrees = angleDegrees(
            px(m.points[0]),
            px(m.points[1]),
            px(m.points[2]),
          );
          _label(
            canvas,
            size,
            degrees == null ? '—' : '${degrees.toStringAsFixed(1)}°',
            points[1],
            lineWidth,
          );
        }
      } else {
        canvas.drawLine(first, last, paint);
        if (m.tool == _Tool.arrow) {
          final a = math.atan2(last.dy - first.dy, last.dx - first.dx);
          final len = math.max(10.0, lineWidth * 6);
          canvas.drawLine(
            last,
            last - Offset(math.cos(a - .45), math.sin(a - .45)) * len,
            paint,
          );
          canvas.drawLine(
            last,
            last - Offset(math.cos(a + .45), math.sin(a + .45)) * len,
            paint,
          );
        }
        if (m.tool == _Tool.axis) {
          final delta = last - first;
          if (delta.distance > 0) {
            final perpendicular =
                Offset(-delta.dy, delta.dx) /
                delta.distance *
                math.min(size.width, size.height) *
                .13;
            final middle = (first + last) / 2;
            canvas.drawLine(
              middle - perpendicular,
              middle + perpendicular,
              paint,
            );
          }
        }
        if (m.tool == _Tool.distance) {
          final pixels = distancePixels(px(m.points.first), px(m.points.last));
          final mm = calibratedDistance(pixels, mmPerPixel: mmPerPixel);
          _label(
            canvas,
            size,
            mm == null
                ? '${pixels.toStringAsFixed(1)} px'
                : '${mm.toStringAsFixed(1)} mm',
            (first + last) / 2,
            lineWidth,
          );
          canvas.drawCircle(first, lineWidth * 2, paint);
          canvas.drawCircle(last, lineWidth * 2, paint);
        }
      }
    }
  }

  void _label(
    Canvas canvas,
    Size size,
    String text,
    Offset position,
    double lineWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: math.max(12.0, lineWidth * 7),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    final x = position.dx.clamp(
      0.0,
      math.max(0.0, size.width - painter.width - 6),
    );
    final y = (position.dy + 5).clamp(
      0.0,
      math.max(0.0, size.height - painter.height - 4),
    );
    final rect = Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      painter.width + 6,
      painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = const Color(0xcc07111d),
    );
    painter.paint(canvas, Offset(x + 3, y + 2));
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => true;
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  _CropPainter(this.crop);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      crop != oldDelegate.crop;
}
