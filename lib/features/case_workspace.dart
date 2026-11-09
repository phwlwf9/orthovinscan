import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_controller.dart';
import '../core/export_cache.dart';
import '../core/models.dart';
import 'camera/capture_screen.dart';
import 'classification/clinical_knowledge.dart';
import 'imaging/imaging_service.dart';
import 'report/report_service.dart';
import 'shell.dart';
import 'viewer/viewer_screen.dart';

PreparedRadiograph _prepare((Uint8List, String) input) =>
    ImagingService.prepare(input.$1, input.$2);

class CaseWorkspace extends StatefulWidget {
  const CaseWorkspace({super.key, this.initialAction, this.initialTab = 0});
  final String? initialAction;
  final int initialTab;
  @override
  State<CaseWorkspace> createState() => _CaseWorkspaceState();
}

class _CaseWorkspaceState extends State<CaseWorkspace> {
  bool importing = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => acquire(widget.initialAction!),
      );
    }
  }

  Future<void> acquire(String action) async {
    final a = context.read<AppController>();
    if (importing) return;
    setState(() => importing = true);
    try {
      Uint8List? bytes;
      String filename = 'radiograph.jpg';
      if (action == 'camera') {
        final photo = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(builder: (_) => CaptureScreen(english: a.english)),
        );
        if (photo == null) return;
        try {
          if (await photo.length() > ImagingService.maxInputBytes) {
            throw const ImagingException(
              'Ảnh quá 50 MB / Image exceeds 50 MB.',
            );
          }
          bytes = await photo.readAsBytes();
          filename = photo.name;
        } finally {
          try {
            await File(photo.path).delete();
          } catch (_) {}
        }
      } else if (action == 'gallery') {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 100,
          requestFullMetadata: false,
        );
        if (photo == null) return;
        if (await photo.length() > ImagingService.maxInputBytes) {
          throw const ImagingException('Ảnh quá 50 MB / Image exceeds 50 MB.');
        }
        bytes = await photo.readAsBytes();
        filename = photo.name;
        // image_picker copies the selected image into the application's cache.
        try {
          await File(photo.path).delete();
        } catch (_) {}
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'jpg',
            'jpeg',
            'png',
            'heic',
            'heif',
            'dcm',
            'dicom',
          ],
          withData: false,
        );
        if (picked == null) return;
        final f = picked.files.single;
        if (f.size > ImagingService.maxInputBytes) {
          throw const ImagingException('Tệp quá 50 MB / File exceeds 50 MB.');
        }
        if (f.path == null) {
          throw const ImagingException(
            'Không đọc được tệp / File is unavailable.',
          );
        }
        bytes = await File(f.path!).readAsBytes();
        filename = f.name;
      }
      final prepared = await compute(_prepare, (bytes, filename));
      if (!mounted) return;
      final r = a.current!;
      r.images.add(
        CaseImage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          originalBytes: bytes,
          pngBytes: prepared.pngBytes,
          sourceFormat: prepared.sourceFormat,
          view: r.images.isEmpty ? 'AP' : 'LAT',
          warning: prepared.warning,
        ),
      );
      a.changed(invalidate: true);
      showMessage(
        context,
        a.tr(
          'Đã nhập ảnh. Kiểm tra hướng và chất lượng ảnh.',
          'Image imported. Check orientation and image quality.',
        ),
      );
    } on ImagingException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          a.tr(
            'Không nhập được ảnh. Kiểm tra quyền camera/ảnh hoặc chọn tệp khác.',
            'Import failed. Check camera/photo permission or choose another file.',
          ),
        );
      }
    } finally {
      if (action != 'camera' && action != 'gallery') {
        try {
          await FilePicker.platform.clearTemporaryFiles();
        } catch (_) {}
      }
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> save() async {
    final a = context.read<AppController>();
    try {
      await a.save();
      if (mounted) {
        showMessage(
          context,
          a.tr(
            'Đã lưu ca mã hóa trên thiết bị.',
            'Encrypted case saved on this device.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          a.tr(
            'Không lưu được. Kiểm tra dung lượng và kho khóa bảo mật.',
            'Could not save. Check free space and secure key storage.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    final r = a.current;
    if (r == null) {
      return const Scaffold(body: Center(child: Text('No active case')));
    }
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${r.id}${a.dirty ? ' •' : ''}',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            IconButton(
              tooltip: a.tr('Lưu ca', 'Save case'),
              onPressed: a.saving ? null : save,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: a.tr('Hình ảnh', 'Images')),
              Tab(text: a.tr('Phân loại', 'Classification')),
              Tab(text: a.tr('Lâm sàng', 'Clinical')),
              Tab(text: a.tr('Hướng xử trí', 'Review pathways')),
              Tab(text: a.tr('Báo cáo', 'Report')),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              ImagePanel(importing: importing, onAcquire: acquire),
              const ClassificationPanel(),
              const ClinicalPanel(),
              const TreatmentPanel(),
              const ReportPanel(),
            ],
          ),
        ),
        bottomNavigationBar: a.dirty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SafeArea(
                  top: false,
                  child: FilledButton.icon(
                    onPressed: a.saving ? null : save,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(
                      a.tr('Lưu ca trên thiết bị', 'Save case on device'),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class ImagePanel extends StatelessWidget {
  const ImagePanel({
    super.key,
    required this.importing,
    required this.onAcquire,
  });
  final bool importing;
  final void Function(String) onAcquire;
  Future<void> viewer(BuildContext context, CaseImage image) async {
    final a = context.read<AppController>();
    final images = a.current!.images;
    final others = images.where((e) => e.id != image.id).toList();
    final result = await Navigator.push<ViewerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewerScreen(
          imageBytes: image.pngBytes,
          initialSession: image.session,
          english: a.english,
          comparisonBytes: others.isEmpty ? null : others.first.displayBytes,
        ),
      ),
    );
    if (result != null) {
      image.editedBytes = result.editedPng;
      image.annotatedBytes = result.annotatedPng;
      image.session = result.session;
      a.changed(invalidate: true);
    }
  }

  Future<void> window(BuildContext context, CaseImage image) async {
    final a = context.read<AppController>();
    try {
      final prepared = await compute(_prepare, (
        image.originalBytes,
        'image.dcm',
      ));
      final dicom = prepared.dicom!;
      final center = TextEditingController(
        text: dicom.defaultWindowCenter.toStringAsFixed(1),
      );
      final width = TextEditingController(
        text: dicom.defaultWindowWidth.toStringAsFixed(1),
      );
      if (!context.mounted) {
        center.dispose();
        width.dispose();
        return;
      }
      final values = await showDialog<(double, double)>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(a.tr('Cửa sổ DICOM', 'DICOM window / level')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.tr(
                    'Áp dụng trên dữ liệu pixel gốc. Tạo bản hiển thị mới sẽ xóa các chỉnh sửa và chú thích hiện tại.',
                    'Applies to original pixel intensities. A new display copy clears current edits and annotations.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: center,
                  decoration: const InputDecoration(
                    labelText: 'Level / Center',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: width,
                  decoration: const InputDecoration(labelText: 'Width (≥ 1)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                if (dicom.orientation != null)
                  Text('Orientation: ${dicom.orientation}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(a.tr('Hủy', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final l = double.tryParse(center.text);
                final w = double.tryParse(width.text);
                if (l != null &&
                    w != null &&
                    l.isFinite &&
                    w.isFinite &&
                    w >= 1) {
                  Navigator.pop(c, (l, w));
                }
              },
              child: Text(a.tr('Áp dụng', 'Apply')),
            ),
          ],
        ),
      );
      center.dispose();
      width.dispose();
      if (values != null && context.mounted) {
        final png = dicom.render(center: values.$1, width: values.$2);
        final i = a.current!.images.indexOf(image);
        a.current!.images[i] = CaseImage(
          id: image.id,
          originalBytes: image.originalBytes,
          pngBytes: png,
          sourceFormat: image.sourceFormat,
          view: image.view,
          warning: image.warning,
        );
        a.changed(invalidate: true);
      }
    } catch (_) {
      if (context.mounted) {
        showMessage(
          context,
          a.tr(
            'Không thể thay đổi cửa sổ DICOM này.',
            'Cannot adjust this DICOM window.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    final r = a.current!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: importing ? null : () => onAcquire('camera'),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(a.tr('Chụp', 'Scan')),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : () => onAcquire('import'),
              icon: const Icon(Icons.upload_file),
              label: Text(a.tr('Tệp / DICOM', 'File / DICOM')),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : () => onAcquire('gallery'),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(a.tr('Thư viện', 'Photos')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'Ảnh gốc được giữ trong ca mã hóa. Nhấn ảnh để xem, đo và chú thích. Kiểm tra tên người bệnh in trong ảnh trước khi xuất.',
            'Originals remain in the encrypted case. Tap an image to view, measure and annotate. Check for burned-in identifiers before export.',
          ),
        ),
        if (importing)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (r.images.isEmpty && !importing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                const Icon(Icons.image_search, size: 64),
                const SizedBox(height: 12),
                Text(
                  a.tr(
                    'Chưa có phim. Nhập ảnh AP và nghiêng khi có.',
                    'No radiographs. Import AP and lateral views when available.',
                  ),
                ),
              ],
            ),
          ),
        for (final image in r.images)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: Text('${image.view} • ${image.sourceFormat}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<String>(
                        value: image.view,
                        items: const [
                          DropdownMenuItem(value: 'AP', child: Text('AP')),
                          DropdownMenuItem(value: 'LAT', child: Text('LAT')),
                          DropdownMenuItem(value: 'OTHER', child: Text('—')),
                        ],
                        onChanged: (v) {
                          image.view = v!;
                          a.changed(invalidate: true);
                        },
                      ),
                      IconButton(
                        tooltip: a.tr('Xóa ảnh', 'Delete image'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text(
                                a.tr(
                                  'Xóa ảnh khỏi ca?',
                                  'Remove image from case?',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: Text(a.tr('Hủy', 'Cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: Text(a.tr('Xóa', 'Remove')),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            r.images.remove(image);
                            a.changed(invalidate: true);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => viewer(context, image),
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: 250,
                    child: Image.memory(
                      image.displayBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (image.warning != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      image.warning!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => viewer(context, image),
                      icon: const Icon(Icons.straighten),
                      label: Text(a.tr('Xem & đo', 'View & measure')),
                    ),
                    if (image.sourceFormat == 'DICOM')
                      TextButton(
                        onPressed: () => window(context, image),
                        child: Text(a.tr('Cửa sổ DICOM', 'DICOM window')),
                      ),
                    TextButton.icon(
                      onPressed: () => shareWithConsent(
                        context,
                        image.displayBytes,
                        '${r.id}-${image.view}.png',
                        'image/png',
                      ),
                      icon: const Icon(Icons.ios_share),
                      label: Text(a.tr('Xuất ảnh', 'Export image')),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ClassificationPanel extends StatelessWidget {
  const ClassificationPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    final r = a.current!;
    final RegionRule? region = r.regionId == null
        ? null
        : a.knowledge.region(r.regionId!);
    final result = region == null
        ? null
        : a.knowledge.evaluate(region.id, r.observations);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          a.tr(
            'Trợ lý phân loại AO/OTA 2018',
            'AO/OTA 2018 classification assistant',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          a.tr(
            'Nhóm lớn A/B/C • người lớn • cần chuyên gia rà soát. Các quan sát do bác sĩ nhập, không suy luận AI từ ảnh.',
            'Adult coarse types A/B/C • pending specialist review. Observations are clinician entered, with no AI image inference.',
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey(r.regionId),
          initialValue: r.regionId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: a.tr('Vùng giải phẫu', 'Anatomical region'),
          ),
          items: a.knowledge.regions
              .map(
                (e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(a.english ? e.nameEn : e.nameVi),
                ),
              )
              .toList(),
          onChanged: (v) {
            r.regionId = v;
            r.observations.clear();
            a.changed(invalidate: true);
          },
        ),
        if (region != null) ...[
          const SizedBox(height: 16),
          Text(a.english ? region.summaryEn : region.summaryVi),
          if (r.images.isEmpty)
            WarningBox(
              a.tr(
                'Chưa nhập ảnh. Cần bác sĩ đánh giá phim đủ chất lượng trước khi xác nhận.',
                'No imported images. Review adequate radiographs before confirmation.',
              ),
            ),
          for (final q in region.questions.where(
            (q) => q.isVisible(r.observations),
          ))
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: DropdownButtonFormField<String>(
                key: ValueKey('${region.id}.${q.id}.${r.observations[q.id]}'),
                initialValue: r.observations[q.id],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      '${a.english ? q.labelEn : q.labelVi}${q.required ? ' *' : ''}',
                  labelStyle: const TextStyle(fontSize: 13),
                ),
                items: q.options
                    .map(
                      (o) => DropdownMenuItem(
                        value: o.id,
                        child: Text(
                          a.english ? o.labelEn : o.labelVi,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  r.observations[q.id] = v;
                  for (final other in region.questions) {
                    if (!other.isVisible(r.observations)) {
                      r.observations.remove(other.id);
                    }
                  }
                  if (q.id == 'adult' && v == 'no') r.clinical['age'] = 'child';
                  a.changed(invalidate: true);
                },
              ),
            ),
          const SizedBox(height: 24),
          if (result != null) ...[
            if (!result.canConfirm)
              WarningBox(
                a.tr(
                  'Không đủ dữ liệu để phân loại chính xác',
                  'Insufficient data for precise classification',
                ),
              ),
            for (final m in a.english ? result.missingEn : result.missing)
              Text('• ${a.tr('Thiếu', 'Missing')}: $m'),
            for (final m in a.english ? result.conflictsEn : result.conflicts)
              WarningBox(m),
            const SizedBox(height: 12),
            Text(
              a.tr('Mã ứng viên', 'Candidate types'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final candidate in result.candidates)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${candidate.code} • ${a.english ? candidate.labelEn : candidate.labelVi}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final evidence
                          in a.english
                              ? candidate.evidenceEn
                              : candidate.evidence)
                        Text('• $evidence'),
                    ],
                  ),
                ),
              ),
            if (result.excluded.isNotEmpty)
              ExpansionTile(
                title: Text(
                  a.tr('Ứng viên không phù hợp', 'Excluded candidates'),
                ),
                children: [
                  for (final c in result.excluded)
                    ListTile(
                      title: Text(c.code),
                      subtitle: Text(
                        (a.english ? c.contradictionsEn : c.contradictions)
                            .join('\n'),
                      ),
                    ),
                ],
              ),
            if (r.clinical['age'] == 'child')
              WarningBox(
                a.tr(
                  'Thông tin lâm sàng ghi trẻ em: ngoài phạm vi bộ quy tắc.',
                  'Clinical assessment indicates a child: outside rule scope.',
                ),
              ),
            const SizedBox(height: 16),
            if (r.confirmedCode != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(
                    '${a.tr('Bác sĩ đã xác nhận', 'Clinician confirmed')}: ${r.confirmedCode}',
                  ),
                  subtitle: Text(
                    '${r.confirmedBy.isEmpty ? a.tr('Không ghi tên bác sĩ', 'Reviewer not entered') : r.confirmedBy}\n${r.confirmedAt?.toLocal()}',
                  ),
                  isThreeLine: true,
                ),
              ),
            FilledButton.icon(
              onPressed:
                  result.canConfirm &&
                      r.images.isNotEmpty &&
                      r.clinical['age'] != 'child'
                  ? () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(
                            a.tr(
                              'Xác nhận của bác sĩ',
                              'Clinician confirmation',
                            ),
                          ),
                          content: Text(
                            a.tr(
                              'Tôi đã xem ảnh, kiểm tra các quan sát và xác nhận nhóm ${result.candidates.single.code}. Đây không phải chẩn đoán AI. Phân nhóm chi tiết cần đánh giá thêm.',
                              'I reviewed the radiographs and observations and confirm type ${result.candidates.single.code}. This is not an AI diagnosis. Detailed subgroups require further review.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(a.tr('Hủy', 'Cancel')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(a.tr('Xác nhận', 'Confirm')),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        r.confirmedCode = result.candidates.single.code;
                        r.confirmedAt = DateTime.now();
                        a.changed();
                      }
                    }
                  : null,
              icon: const Icon(Icons.verified_outlined),
              label: Text(
                a.tr(
                  'Bác sĩ xác nhận phân loại',
                  'Clinician: confirm classification',
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  openReference(context, region.referenceUrls.first),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in AO Surgery Reference'),
            ),
          ],
        ],
      ],
    );
  }
}

class ClinicalPanel extends StatelessWidget {
  const ClinicalPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    final r = a.current!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          a.tr('Đánh giá lâm sàng', 'Clinical assessment'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          a.tr(
            'Không có thông tin không có nghĩa là bình thường. Không nhập danh tính người bệnh.',
            'Unknown does not mean normal. Do not enter patient identifiers.',
          ),
        ),
        for (final flag in redFlags(r.clinical, english: a.english))
          WarningBox(flag),
        if (redFlags(r.clinical).isNotEmpty)
          Text(
            a.tr(
              'Đây là nhắc nhở an toàn, không phải chẩn đoán.',
              'These are safety prompts, not diagnoses.',
            ),
          ),
        for (final f in clinicalFields)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: DropdownButtonFormField<String>(
              key: ValueKey('${f.id}.${r.clinical[f.id]}'),
              initialValue: r.clinical[f.id] ?? 'unknown',
              isExpanded: true,
              decoration: InputDecoration(labelText: a.english ? f.en : f.vi),
              items: [
                DropdownMenuItem(
                  value: 'unknown',
                  child: Text(
                    a.tr('Chưa rõ / chưa đánh giá', 'Unknown / not assessed'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                for (final o in f.options)
                  DropdownMenuItem(
                    value: o.$1,
                    child: Text(
                      a.english ? o.$3 : o.$2,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (v) {
                r.clinical[f.id] = v!;
                if (f.id == 'age') {
                  r.observations['adult'] = v == 'child'
                      ? 'no'
                      : v == 'unknown'
                      ? 'unknown'
                      : 'yes';
                }
                a.changed(invalidate: true);
              },
            ),
          ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: r.clinical['notes'] ?? '',
          minLines: 3,
          maxLines: 7,
          maxLength: 3000,
          decoration: InputDecoration(
            labelText: a.tr(
              'Ghi chú lâm sàng (không thông tin định danh)',
              'Clinical notes (no patient identifiers)',
            ),
          ),
          onChanged: (v) {
            r.clinical['notes'] = v;
            a.changed(invalidate: true);
          },
        ),
      ],
    );
  }
}

class TreatmentPanel extends StatelessWidget {
  const TreatmentPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    final r = a.current!;
    final region = r.regionId == null ? null : a.knowledge.region(r.regionId!);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          a.tr('Hỗ trợ xem xét hướng điều trị', 'Treatment considerations'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        WarningBox(
          a.tr(
            'Nội dung giáo dục có nguồn tham khảo, chưa được thẩm định trong ứng dụng. Cần bác sĩ đánh giá thêm.',
            'Referenced educational content, not clinically validated in this app. Further clinician assessment is required.',
          ),
        ),
        for (final flag in redFlags(r.clinical, english: a.english))
          WarningBox(flag),
        if (region == null || r.confirmedCode == null)
          Text(
            a.tr(
              'Chọn vùng và hoàn tất xác nhận phân loại trước khi xem các yếu tố điều trị.',
              'Select a region and confirm the classification to review treatment factors.',
            ),
          ),
        if (region != null && r.confirmedCode != null) ...[
          Card(
            child: ListTile(
              title: Text(
                '${a.english ? region.nameEn : region.nameVi} • ${r.confirmedCode}',
              ),
              subtitle: Text(
                '${clinicalLabel('side', r.clinical['side'], english: a.english)}\n${a.tr('Quan sát và phân loại do bác sĩ xác nhận.', 'Observations and classification confirmed by clinician.')}',
              ),
              isThreeLine: true,
            ),
          ),
          Text(
            a.tr('Dữ liệu lâm sàng còn thiếu', 'Missing clinical information'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final f in clinicalFields.where(
            (f) => r.clinical[f.id] == null || r.clinical[f.id] == 'unknown',
          ))
            Text('• ${a.english ? f.en : f.vi}'),
          const SizedBox(height: 16),
          for (final section in region.treatmentSections)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.english ? section.titleEn : section.titleVi,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(a.english ? section.bodyEn : section.bodyVi),
                    for (final url in section.sourceUrls)
                      TextButton.icon(
                        onPressed: () => openReference(context, url),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(
                          a.tr('Nguồn: AO Foundation', 'Source: AO Foundation'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => openReference(context, region.referenceUrls.first),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in AO Surgery Reference'),
          ),
        ],
      ],
    );
  }
}

class ReportPanel extends StatelessWidget {
  const ReportPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    final r = a.current!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          a.tr('Báo cáo ca', 'Case report'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: r.findings,
          minLines: 4,
          maxLines: 10,
          maxLength: 5000,
          decoration: InputDecoration(
            labelText: a.tr(
              'Nhận xét hình ảnh do bác sĩ nhập',
              'Clinician-entered radiographic findings',
            ),
          ),
          onChanged: (v) {
            r.findings = v;
            a.changed(invalidate: true);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: r.confirmedBy,
          maxLength: 150,
          decoration: InputDecoration(
            labelText: a.tr(
              'Bác sĩ rà soát (tùy chọn)',
              'Reviewing clinician (optional)',
            ),
          ),
          onChanged: (v) {
            r.confirmedBy = v;
            a.changed();
          },
        ),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'Báo cáo dùng ảnh hiển thị hiện tại và chú thích đã lưu. Phân loại chưa xác nhận được ghi rõ. Không đưa metadata DICOM vào PDF; kiểm tra thông tin in sẵn trong ảnh.',
            'The report uses current display copies and saved annotations. Unconfirmed classifications are labeled. DICOM metadata is omitted; check burned-in image information.',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () async {
            try {
              final bytes = await makeReport(a);
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReportPreview(bytes: bytes, caseId: r.id),
                  ),
                );
              }
            } catch (_) {
              if (context.mounted) {
                showMessage(
                  context,
                  a.tr(
                    'Không tạo được PDF. Kiểm tra bộ nhớ và ảnh.',
                    'Could not generate PDF. Check memory and images.',
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(a.tr('Tạo & xem PDF', 'Generate & preview PDF')),
        ),
      ],
    );
  }
}

Future<Uint8List> makeReport(AppController a) async {
  final r = a.current!;
  final region = r.regionId == null ? null : a.knowledge.region(r.regionId!);
  final labels = <String, String>{};
  if (region != null) {
    for (final q in region.questions) {
      final selected = q.options.where((o) => o.id == r.observations[q.id]);
      if (selected.isNotEmpty) {
        labels[q.id] =
            '${a.english ? q.labelEn : q.labelVi}: ${a.english ? selected.first.labelEn : selected.first.labelVi}';
      }
    }
  }
  return ReportService.build(
    r,
    regionName: region == null
        ? a.tr('Chưa chọn', 'Not selected')
        : a.english
        ? region.nameEn
        : region.nameVi,
    treatmentNotes: r.confirmedCode == null
        ? []
        : region?.treatmentSections
                  .map(
                    (s) =>
                        '${a.english ? s.titleEn : s.titleVi}: ${a.english ? s.bodyEn : s.bodyVi}',
                  )
                  .toList() ??
              [],
    references: {
      ...?region?.referenceUrls,
      ...?region?.treatmentSections.expand((s) => s.sourceUrls),
    }.toList(),
    missing: [
      if (r.confirmedCode == null)
        a.tr(
          'Phân loại chưa được bác sĩ xác nhận',
          'Classification not clinician confirmed',
        ),
      for (final f in clinicalFields.where(
        (f) => r.clinical[f.id] == null || r.clinical[f.id] == 'unknown',
      ))
        a.english ? f.en : f.vi,
    ],
    observationLabels: labels,
    english: a.english,
  );
}

Future<void> shareWithConsent(
  BuildContext context,
  Uint8List bytes,
  String name,
  String mimeType,
) async {
  final a = context.read<AppController>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(a.tr('Cho phép xuất / chia sẻ?', 'Allow export / sharing?')),
      content: Text(
        a.tr(
          'Bản sao không mã hóa có thể được gửi tới ứng dụng khác. Tôi đã kiểm tra thông tin định danh trong ảnh và có quyền chia sẻ nội dung này.',
          'An unencrypted copy may be sent to another app. I checked the images for patient identifiers and am authorized to share this content.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(a.tr('Hủy', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(a.tr('Cho phép', 'Allow')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final box = context.findRenderObject() as RenderBox?;
    final file = await ExportCache.prepare(bytes, name);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: name)],
        fileNameOverrides: [name],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        a.tr('Không mở được chia sẻ.', 'Could not open sharing.'),
      );
    }
  }
}

class ReportPreview extends StatelessWidget {
  const ReportPreview({super.key, required this.bytes, required this.caseId});
  final Uint8List bytes;
  final String caseId;
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(a.tr('Xem báo cáo PDF', 'PDF report preview')),
        actions: [
          IconButton(
            tooltip: a.tr('Xuất PDF', 'Export PDF'),
            onPressed: () => shareWithConsent(
              context,
              bytes,
              '$caseId.pdf',
              'application/pdf',
            ),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}

class WarningBox extends StatelessWidget {
  const WarningBox(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
