# Kiến trúc OrthoAI

Một codebase Flutter tạo ứng dụng native Android và iOS. Không cần backend cho thao tác cơ bản; mạng chỉ cần khi mở nguồn tham khảo hoặc khi người dùng chủ động dùng đích chia sẻ bên ngoài.

## Các lớp chính

| Mô-đun | Trách nhiệm |
| --- | --- |
| `lib/main.dart` | Khởi động, mở kho an toàn, tải knowledge base, locale và theme Material 3 |
| `lib/core/app_controller.dart` | ChangeNotifier qua Provider; ca hiện tại, trạng thái chưa lưu, xác nhận, thiết lập |
| `lib/core/models.dart` | `CaseRecord`, `CaseImage`, trường lâm sàng và lời nhắc nguy cấp |
| `lib/core/case_repository.dart` | AES-256-GCM, khóa trong secure storage, ghi tệp thay thế nguyên tử, CRUD ca |
| `lib/core/export_cache.dart` | Tạo bản xuất tạm sau consent, dọn cache xuất khi khởi động lại |
| `lib/features/shell.dart` | Đồng ý sử dụng, tổng quan, ca đã lưu, tài liệu và cài đặt |
| `lib/features/case_workspace.dart` | Điều phối thao tác theo ca: ảnh, phân loại, khám, hỗ trợ và báo cáo |
| `lib/features/imaging/` | Kiểm tra/giải mã ảnh, DICOM, chỉ số chất lượng kỹ thuật, contract suy luận tương lai |
| `lib/features/viewer/` | Transform ảnh, tọa độ chú thích, đo thủ công, hiệu chuẩn và render bản sao |
| `lib/features/classification/clinical_knowledge.dart` | Engine xác định: ứng viên, loại trừ, thiếu dữ liệu, mâu thuẫn; không tự xác nhận |
| `assets/clinical_rules/ao_ota_2018.json` | Quy tắc phiên bản, nguồn, URL đã kiểm tra và tóm tắt gốc chờ chuyên gia duyệt |
| `lib/features/report/report_service.dart` | PDF ngoại tuyến, font tiếng Việt, phân biệt nhận xét nhập tay và trạng thái xác nhận |

## Vòng đời ca

`Tạo/nhập ảnh → bản gốc + PNG dựng lại → chỉnh sửa/chú thích → quan sát do bác sĩ nhập → ứng viên phân loại → bác sĩ xác nhận → khám và tham khảo → lưu/xuất chủ động`.

Bản gốc giữ nguyên trong vùng ca mã hóa. Các bản PNG hiển thị và bản chú thích được lưu riêng. Session trình xem lưu transform/đánh dấu để chỉnh sửa tiếp. Khoảng cách tính trong hệ tọa độ ảnh, không phụ thuộc mức zoom; đơn vị mm chỉ có khi hiệu chuẩn được xác nhận. Thay đổi quan sát liên quan phải làm mất xác nhận cũ.

## Biên dữ liệu

- Không có telemetry, API key, endpoint inference hoặc upload tự động.
- Kho ca mã hóa cả thông tin và ảnh bằng AES-256-GCM, nonce ngẫu nhiên, AAD gắn ID và schema. ID được giới hạn ký tự để tránh traversal.
- Khóa 32 byte được sinh bằng nguồn ngẫu nhiên an toàn và giữ qua `flutter_secure_storage`; không nằm trong source hoặc file ca.
- Tệp mã hóa bị lỗi/không giải mã được được giữ lại; không tự đổi khóa và ghi đè. File tạm khi lưu cũng đã mã hóa.
- Lịch sử giữ tóm tắt không chứa ảnh trong bộ nhớ; ảnh đầy đủ chỉ nạp khi mở ca. Một tệp ca không đọc được được liệt kê riêng để người dùng xử lý, không chặn các ca lành. Duyệt lịch sử vẫn phải giải mã lần lượt từng ca, nên thư viện rất lớn cần chỉ mục mã hóa riêng ở phiên bản sau.
- Thao tác lưu dùng snapshot và số phiên bản thay đổi; chỉnh sửa xảy ra trong lúc lưu vẫn được đánh dấu chưa lưu. Các lần bấm lưu đồng thời dùng chung thao tác đang chạy.
- Preferences chỉ chứa ngôn ngữ, theme và trạng thái consent; dữ liệu lâm sàng không nằm trong SharedPreferences thường.
- PDF được dựng từ dữ liệu chọn lọc và PNG, không serialize metadata gốc. Đầu ra chia sẻ không được mã hóa bởi kho ca.
- Android tắt OS backup cho app. iOS có thể sao lưu tệp mã hóa theo chính sách hệ điều hành; khóa Keychain chỉ dành cho thiết bị này, nên không có bảo đảm phục hồi trên thiết bị khác. Ứng dụng không triển khai chức năng sao lưu/khôi phục.
- Tệp tạm do file picker được dọn sau nhập; ảnh camera bị hủy được dọn. PDF/PNG xuất tạm và cache share_plus được dọn ở lần khởi động tiếp theo để không cắt quyền đọc của ứng dụng nhận trong khi chia sẻ. Không thể thu hồi bản sao đã chuyển ra ngoài.

## DICOM

Bộ đọc giới hạn Part 10, transfer syntax implicit/explicit VR little endian không nén, một frame, MONOCHROME1/2. Xử lý signed pixel, Bits Stored/High Bit, rescale và window/level; kiểm tra kích thước và độ dài buffer. Syntax nén, nhiều frame và cấu trúc không hỗ trợ được báo lỗi rõ ràng. Không dùng patient tags để đặt tên ca hoặc ghi log. Hướng ảnh phải được bác sĩ xác minh; không tự khẳng định hướng giải phẫu từ ảnh chụp phim.

## Mở rộng

Thêm vùng bằng dữ liệu có phiên bản, câu hỏi, tiêu chí, mâu thuẫn và nguồn; bổ sung test xác định và review lâm sàng. Giữ nội dung AO có giấy phép tách khỏi logic engine.

`FractureInferenceService` quy định tính sẵn có, metadata mô hình, vùng, ứng viên và bất định. Adapter hiện tại luôn báo không có mô hình. Adapter ONNX/TFLite/cloud sau này phải có trọng số hợp lệ, giấy phép, pipeline đúng contract và đánh giá độc lập; cloud cần consent riêng trước gửi ảnh. Một model tải được không có nghĩa đã được thẩm định.
