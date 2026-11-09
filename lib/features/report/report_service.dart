import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models.dart';

/// Generates a fully offline report. Callers must obtain explicit permission
/// before handing these bytes to a print/share/export destination.
class ReportService {
  static Future<Uint8List> build(
    CaseRecord record, {
    required String regionName,
    required List<String> treatmentNotes,
    required List<String> references,
    required List<String> missing,
    Map<String, String> observationLabels = const {},
    bool english = false,
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final document = pw.Document(
      title: 'OrthoAI ${record.id}',
      author: 'OrthoAI',
      creator: 'OrthoAI 0.1.0',
      subject: english
          ? 'Clinician-reviewed research / educational prototype'
          : 'Nguyên mẫu nghiên cứu / giáo dục có bác sĩ đánh giá',
    );
    String t(String vi, String en) => english ? en : vi;
    final unknown = t('Chưa rõ / chưa đánh giá', 'Unknown / not assessed');
    final ink = PdfColor.fromHex('#123C4A');
    final muted = PdfColor.fromHex('#52616B');
    final pale = PdfColor.fromHex('#EAF5F2');
    final now = DateTime.now().toLocal();
    String date(DateTime value) {
      final v = value.toLocal();
      String p(int n) => n.toString().padLeft(2, '0');
      return '${p(v.day)}/${p(v.month)}/${v.year} ${p(v.hour)}:${p(v.minute)}';
    }

    pw.Widget section(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 7),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: ink,
        ),
      ),
    );
    pw.Widget paragraph(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
    );
    pw.Widget row(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 155,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 10, color: muted),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
    final confirmed =
        record.confirmedCode != null && record.confirmedAt != null;
    final warnings = redFlags(record.clinical, english: english);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(35, 32, 35, 36),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        maxPages: 40,
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 16),
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: ink, width: 1.2)),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 29,
                height: 29,
                decoration: pw.BoxDecoration(
                  color: ink,
                  borderRadius: pw.BorderRadius.circular(7),
                ),
                child: pw.Center(
                  child: pw.Text(
                    '+',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      font: bold,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'OrthoAI',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    pw.Text(
                      t(
                        'Báo cáo hỗ trợ đánh giá',
                        'Clinical assessment support report',
                      ),
                      style: pw.TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ),
              pw.Text(
                record.id,
                style: pw.TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'OrthoAI 0.1.0 • AO/OTA 2018',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
              pw.Text(
                '${context.pageNumber}/${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: pale,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Text(
              t(
                'Nguyên mẫu nghiên cứu / giáo dục. Phân loại do bác sĩ nhập và xác nhận; chưa được xác thực cho chẩn đoán tự động.',
                'Research / educational prototype. Classification is entered and confirmed by a clinician; not validated for autonomous diagnosis.',
              ),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.NewPage(freeSpace: 70),
          section(t('Tóm tắt ca', 'Case summary')),
          row(t('Ngày lập báo cáo', 'Report date'), date(now)),
          row(t('Ca ẩn danh', 'Anonymized case'), record.id),
          row(t('Ngày tạo ca', 'Case created'), date(record.createdAt)),
          row(t('Vùng giải phẫu', 'Anatomical region'), regionName),
          row(
            t('Bên tổn thương', 'Side'),
            clinicalLabel('side', record.clinical['side'], english: english),
          ),
          row(
            'AO/OTA 2018',
            confirmed
                ? record.confirmedCode!
                : t(
                    'Chưa có phân loại được bác sĩ xác nhận',
                    'No clinician-confirmed classification',
                  ),
          ),
          if (confirmed)
            row(
              t('Thời điểm xác nhận', 'Confirmation date'),
              date(record.confirmedAt!),
            ),
          row(
            t('Bác sĩ đánh giá', 'Reviewing clinician'),
            record.confirmedBy.trim().isEmpty
                ? unknown
                : record.confirmedBy.trim(),
          ),
          pw.NewPage(freeSpace: 70),
          section(t('Nhận xét do bác sĩ nhập', 'Clinician-entered findings')),
          paragraph(
            record.findings.trim().isEmpty ? unknown : record.findings.trim(),
          ),
          if (observationLabels.isNotEmpty) ...[
            for (final entry in observationLabels.entries)
              row(entry.key, entry.value),
          ] else if (record.observations.isNotEmpty)
            paragraph(
              t(
                'Các lựa chọn hình thái được lưu trong trợ lý phân loại của ca; xem lại với bác sĩ đánh giá.',
                'Morphology selections are retained in the case classification assistant; review with the assessing clinician.',
              ),
            ),
          pw.NewPage(freeSpace: 70),
          section(
            t(
              'Đánh giá lâm sàng do người dùng nhập',
              'User-entered clinical assessment',
            ),
          ),
          for (final field in clinicalFields)
            row(
              english ? field.en : field.vi,
              clinicalLabel(
                field.id,
                record.clinical[field.id],
                english: english,
              ),
            ),
          if (record.clinical['notes']?.trim().isNotEmpty ?? false)
            row(t('Ghi chú', 'Notes'), record.clinical['notes']!),
          if (warnings.isNotEmpty) ...[
            pw.NewPage(freeSpace: 70),
            section(
              t('Dấu hiệu cần đánh giá khẩn', 'Urgent assessment prompts'),
            ),
            for (final warning in warnings) paragraph(warning),
            paragraph(
              t(
                'Đây là nhắc nhở an toàn, không phải chẩn đoán.',
                'These are safety prompts, not diagnoses.',
              ),
            ),
          ],
          pw.NewPage(freeSpace: 70),
          section(t('Thông tin còn thiếu', 'Missing information')),
          if (missing.isEmpty)
            paragraph(
              t(
                'Không có mục thiếu được đánh dấu; bác sĩ vẫn cần đánh giá tính đầy đủ của dữ liệu.',
                'No missing items flagged; the clinician must still assess data completeness.',
              ),
            )
          else
            for (final item in missing) paragraph('• $item'),
          pw.NewPage(freeSpace: 70),
          section(
            t(
              'Các hướng điều trị cần thảo luận',
              'Treatment options to review',
            ),
          ),
          if (!confirmed)
            paragraph(
              t(
                'Cần bác sĩ xác nhận phân loại trước khi diễn giải hỗ trợ điều trị theo ca.',
                'Clinician confirmation is needed before interpreting case-specific treatment support.',
              ),
            ),
          if (treatmentNotes.isEmpty)
            paragraph(
              t(
                'Cần bác sĩ đánh giá thêm.',
                'Further clinician assessment is required.',
              ),
            )
          else
            for (final note in treatmentNotes) paragraph(note),
          pw.NewPage(freeSpace: 70),
          section(t('Tài liệu tham khảo', 'References')),
          if (references.isEmpty)
            paragraph(
              'AO Surgery Reference — AO Foundation\nhttps://surgeryreference.aofoundation.org/',
            )
          else
            for (final reference in references) paragraph(reference),
          paragraph(
            t(
              'Trích yếu giáo dục gốc; nội dung cần bác sĩ chuyên khoa rà soát. Không sao chép hình hoặc sơ đồ AO.',
              'Original educational summaries; specialist review is required. No AO figures or diagrams are reproduced.',
            ),
          ),
          pw.NewPage(freeSpace: 70),
          section(t('Giới hạn báo cáo', 'Report limitations')),
          paragraph(
            'This report is a clinical decision-support document and does not replace specialist assessment.',
          ),
          if (!english)
            paragraph(
              'Báo cáo hỗ trợ quyết định lâm sàng, không thay thế đánh giá chuyên khoa.',
            ),
          paragraph(
            t(
              'Không có kết quả AI chẩn đoán trong phiên bản này. Đo đạc là tính toán hình học do người dùng đặt mốc; đơn vị pixel trừ khi người dùng hiệu chuẩn. Ảnh chụp phim không tương đương ảnh X-quang gốc.',
              'This version contains no diagnostic AI result. Measurements are geometric calculations on user-placed landmarks; units are pixels unless explicitly calibrated. Film photographs are not equivalent to original radiographs.',
            ),
          ),
        ],
      ),
    );
    // Separate image pages keep the narrative and each radiograph legible.
    for (final image in record.images) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(35),
          theme: pw.ThemeData.withFont(base: font, bold: bold),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'OrthoAI · ${record.id} · ${image.view}',
                style: pw.TextStyle(
                  fontSize: 15,
                  color: ink,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(image.displayBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
              paragraph(
                t(
                  'Ảnh đã xử lý / chú thích theo lựa chọn của người dùng. Mốc chú thích và phát hiện do người dùng nhập; không phải dự đoán AI. Không xuất siêu dữ liệu DICOM. Kiểm tra chữ nhận diện còn nằm trong điểm ảnh trước khi chia sẻ.',
                  'User-selected processed / annotated image. Landmarks and findings are user-entered, not AI predictions. DICOM metadata is not exported. Check for identifiers burned into pixels before sharing.',
                ),
              ),
              paragraph(
                'This report is a clinical decision-support document and does not replace specialist assessment.',
              ),
              pw.Text(
                'OrthoAI 0.1.0',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
      );
    }
    return document.save();
  }
}
