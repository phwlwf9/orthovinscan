import 'dart:convert';
import 'dart:typed_data';

class CaseImage {
  CaseImage({
    required this.id,
    required this.originalBytes,
    required this.pngBytes,
    required this.sourceFormat,
    this.view = 'AP',
    this.warning,
    this.annotatedBytes,
    this.editedBytes,
    Map<String, dynamic>? session,
  }) : session = session ?? {};
  final String id;
  final Uint8List originalBytes;
  final Uint8List pngBytes;
  final String sourceFormat;
  String view;
  String? warning;
  Uint8List? annotatedBytes;
  Uint8List? editedBytes;
  Map<String, dynamic> session;
  Uint8List get displayBytes => annotatedBytes ?? editedBytes ?? pngBytes;
  Map<String, dynamic> toJson() => {
    'id': id,
    'original': base64Encode(originalBytes),
    'png': base64Encode(pngBytes),
    'format': sourceFormat,
    'view': view,
    'warning': warning,
    'session': session,
    if (annotatedBytes != null) 'annotated': base64Encode(annotatedBytes!),
    if (editedBytes != null) 'edited': base64Encode(editedBytes!),
  };
  factory CaseImage.fromJson(Map<String, dynamic> j) => CaseImage(
    id: j['id'] as String,
    originalBytes: base64Decode(j['original'] as String),
    pngBytes: base64Decode(j['png'] as String),
    sourceFormat: j['format'] as String,
    view: j['view'] as String? ?? 'AP',
    warning: j['warning'] as String?,
    session: Map<String, dynamic>.from(j['session'] as Map? ?? {}),
    annotatedBytes: j['annotated'] == null
        ? null
        : base64Decode(j['annotated'] as String),
    editedBytes: j['edited'] == null
        ? null
        : base64Decode(j['edited'] as String),
  );
}

class CaseRecord {
  CaseRecord({
    required this.id,
    required this.createdAt,
    DateTime? updatedAt,
    this.regionId,
    this.confirmedCode,
    this.confirmedBy = '',
    this.confirmedAt,
    this.findings = '',
    this.summaryImageCount,
    Map<String, String>? observations,
    Map<String, String>? clinical,
    List<CaseImage>? images,
  }) : updatedAt = updatedAt ?? createdAt,
       observations = observations ?? {},
       clinical = clinical ?? {},
       images = images ?? [];
  final String id;
  final DateTime createdAt;
  DateTime updatedAt;
  String? regionId;
  String? confirmedCode;
  String confirmedBy;
  DateTime? confirmedAt;
  String findings;
  Map<String, String> observations;
  Map<String, String> clinical;
  List<CaseImage> images;

  /// In-memory history metadata only; full cases always load without this flag.
  final int? summaryImageCount;
  int get imageCount => summaryImageCount ?? images.length;

  /// Keeps history lightweight while preserving the count of stored images.
  /// This object must be reloaded from the repository before editing or saving.
  CaseRecord summary() => CaseRecord(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt,
    regionId: regionId,
    confirmedCode: confirmedCode,
    confirmedBy: confirmedBy,
    confirmedAt: confirmedAt,
    findings: findings,
    observations: Map<String, String>.from(observations),
    clinical: Map<String, String>.from(clinical),
    summaryImageCount: imageCount,
  );

  void invalidateConfirmation() {
    confirmedCode = null;
    confirmedAt = null;
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'regionId': regionId,
    'confirmedCode': confirmedCode,
    'confirmedBy': confirmedBy,
    'confirmedAt': confirmedAt?.toIso8601String(),
    'findings': findings,
    'observations': observations,
    'clinical': clinical,
    'images': images.map((e) => e.toJson()).toList(),
  };
  factory CaseRecord.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1) {
      throw const FormatException('Unsupported case schema');
    }
    return CaseRecord(
      id: j['id'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      regionId: j['regionId'] as String?,
      confirmedCode: j['confirmedCode'] as String?,
      confirmedBy: j['confirmedBy'] as String? ?? '',
      confirmedAt: j['confirmedAt'] == null
          ? null
          : DateTime.parse(j['confirmedAt'] as String),
      findings: j['findings'] as String? ?? '',
      observations: Map<String, String>.from(j['observations'] as Map? ?? {}),
      clinical: Map<String, String>.from(j['clinical'] as Map? ?? {}),
      images: (j['images'] as List)
          .map((e) => CaseImage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class ClinicalField {
  const ClinicalField(this.id, this.vi, this.en, this.options);
  final String id, vi, en;
  final List<(String, String, String)> options;
}

const clinicalFields = <ClinicalField>[
  ClinicalField('age', 'Nhóm tuổi', 'Age group', [
    (
      'child',
      'Trẻ em — ngoài phạm vi phân loại',
      'Child — classification out of scope',
    ),
    ('adult', 'Người lớn', 'Adult'),
    ('older', 'Người cao tuổi', 'Older adult'),
  ]),
  ClinicalField('side', 'Bên tổn thương', 'Side', [
    ('left', 'Trái', 'Left'),
    ('right', 'Phải', 'Right'),
  ]),
  ClinicalField('mechanism', 'Cơ chế chấn thương', 'Injury mechanism', [
    ('low', 'Năng lượng thấp', 'Low energy'),
    ('high', 'Năng lượng cao', 'High energy'),
  ]),
  ClinicalField('time', 'Thời gian từ chấn thương', 'Time since injury', [
    ('acute', 'Dưới 24 giờ', 'Under 24 hours'),
    ('days', '1–7 ngày', '1–7 days'),
    ('late', 'Trên 7 ngày', 'Over 7 days'),
  ]),
  ClinicalField('open', 'Kín / hở', 'Closed / open', [
    ('closed', 'Kín', 'Closed'),
    ('open', 'Nghi ngờ / xác định gãy hở', 'Suspected / confirmed open'),
  ]),
  ClinicalField('soft', 'Phần mềm', 'Soft tissues', [
    ('intact', 'Không ghi nhận tổn thương', 'No injury identified'),
    ('injured', 'Có tổn thương', 'Injury identified'),
  ]),
  ClinicalField('vascular', 'Tưới máu chi', 'Limb perfusion', [
    ('normal', 'Đã khám: không bất thường', 'Examined: no abnormality'),
    ('compromised', 'Nghi ngờ giảm tưới máu', 'Suspected vascular compromise'),
  ]),
  ClinicalField('nerve', 'Thần kinh', 'Neurological status', [
    ('normal', 'Đã khám: không bất thường', 'Examined: no abnormality'),
    ('abnormal', 'Có bất thường', 'Abnormal findings'),
  ]),
  ClinicalField(
    'compartment',
    'Hội chứng chèn ép khoang',
    'Compartment syndrome',
    [
      ('no', 'Đã đánh giá: chưa nghi ngờ', 'Assessed: not suspected'),
      ('suspected', 'Nghi ngờ', 'Suspected'),
    ],
  ),
  ClinicalField('associated', 'Tổn thương phối hợp', 'Associated injuries', [
    ('none', 'Đã đánh giá: chưa ghi nhận', 'Assessed: none identified'),
    ('yes', 'Có — mô tả trong ghi chú', 'Present — describe in notes'),
  ]),
  ClinicalField('comorbidities', 'Bệnh đồng mắc', 'Comorbidities', [
    ('none', 'Đã khai thác: chưa ghi nhận', 'Assessed: none identified'),
    ('present', 'Có — mô tả trong ghi chú', 'Present — describe in notes'),
  ]),
  ClinicalField('function', 'Nhu cầu chức năng', 'Functional needs', [
    ('independent', 'Độc lập trước chấn thương', 'Previously independent'),
    ('limited', 'Có hạn chế trước chấn thương', 'Previously limited'),
  ]),
  ClinicalField('risk', 'Nguy cơ phẫu thuật', 'Surgical risk', [
    ('assessed', 'Đã đánh giá — xem ghi chú', 'Assessed — see notes'),
    ('concern', 'Có yếu tố nguy cơ', 'Risk factors present'),
  ]),
];

List<String> redFlags(Map<String, String> values, {bool english = false}) => [
  if (values['open'] == 'open')
    english
        ? 'Possible open fracture: urgent specialist assessment.'
        : 'Nghi ngờ gãy hở: cần đánh giá chuyên khoa khẩn.',
  if (values['vascular'] == 'compromised')
    english
        ? 'Possible vascular compromise: urgent assessment.'
        : 'Nghi ngờ giảm tưới máu chi: cần đánh giá khẩn.',
  if (values['compartment'] == 'suspected')
    english
        ? 'Possible acute compartment syndrome: urgent assessment.'
        : 'Nghi ngờ chèn ép khoang cấp: cần đánh giá khẩn.',
];

String clinicalLabel(String key, String? value, {bool english = false}) {
  for (final f in clinicalFields) {
    if (f.id == key) {
      for (final o in f.options) {
        if (o.$1 == value) return english ? o.$3 : o.$2;
      }
    }
  }
  return english ? 'Unknown / not assessed' : 'Chưa rõ / chưa đánh giá';
}
