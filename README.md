# OrthoAI

Ứng dụng Flutter chạy cục bộ để nhân viên y tế xem phim, đo, chú thích và thực hiện phân loại AO/OTA có giải thích. Tiếng Việt mặc định; có tiếng Anh và giao diện sáng/tối.

**Bản nghiên cứu / giáo dục 0.1.0, chưa được thẩm định chẩn đoán hoặc chứng nhận thiết bị y tế. Không có mô hình AI chẩn đoán.** Phân loại do bác sĩ nhập và xác nhận; nội dung lâm sàng đang chờ chuyên gia rà soát. Không dùng ứng dụng để tự quyết định điều trị.

## Gói bàn giao 0.1.0

- [APK Android — bản phát triển ký debug](release/OrthoAI-Android.apk) (65.099.996 byte; Android 7.0+, ARM64). Trong trang tệp GitHub, chọn **Download raw file** để tải.
- [Mã nguồn Flutter đóng gói](release/OrthoAI-Flutter-source.zip).
- [Báo cáo build và giới hạn đã xác minh](release/BUILD_VERIFICATION.md).
- [Checksum SHA-256](release/SHA256SUMS.txt).
- [Trạng thái bàn giao và CI GitHub](docs/GITHUB_CI_STATUS.md).

Không có IPA có chữ ký trong gói. Xem `docs/BUILD_IOS.md` để build/ký trên macOS bằng Xcode. Chưa kiểm thử trên điện thoại thật; đây là bản nghiên cứu/giáo dục cần chuyên gia rà soát.

## Bắt đầu

Yêu cầu Flutter **3.47.9 stable** / Dart **3.13.7**, Android SDK hoặc macOS/Xcode khi build iOS. Giữ `pubspec.lock` để tái lập phiên bản dependency.

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter run
```

Trong workspace build của phiên phát triển này, toolchain nằm ngoài source:

```bash
source /workspace/work/tools/env.sh
```

Không cần đường dẫn đó trên máy cá nhân nếu Flutter và Android SDK đã được cấu hình.

## Luồng sử dụng

1. Đọc giới hạn sử dụng và đồng ý xử lý cục bộ ở lần mở đầu.
2. Tạo ca ẩn danh. Chụp phim hoặc nhập JPEG/PNG/DICOM; gán tư thế AP/nghiêng. Kiểm tra ảnh không chứa thông tin định danh in trực tiếp.
3. Mở trình xem để phóng to, xoay, cắt, điều chỉnh, chú thích và đo. Khoảng cách ở đơn vị pixel cho tới khi bác sĩ xác nhận hiệu chuẩn hợp lệ.
4. Ghi nhận khám lâm sàng và nhận xét hình ảnh. “Chưa rõ” khác với “đã khám: bình thường”. Dấu hiệu nguy cấp là lời nhắc đánh giá khẩn, không phải chẩn đoán.
5. Chọn vùng giải phẫu và trả lời trợ lý AO/OTA. Xem dữ liệu còn thiếu, bằng chứng hỗ trợ và mâu thuẫn; chỉ xác nhận sau khi bác sĩ kiểm tra. Nếu sửa ảnh, quan sát, nhận xét hoặc dữ liệu lâm sàng sau đó, quay lại xác nhận phân loại trước khi xem phần điều trị.
6. Xem tóm tắt giáo dục và mở tài liệu AO chính thức. Lưu ca trên thiết bị; xem trước PDF và chủ động cho phép xuất/chia sẻ khi phù hợp.

Xem [báo cáo build thực tế](docs/BUILD_VERIFICATION.md) để biết kết quả kiểm tra, artifact đã tạo và phần chưa xác minh.

## Phạm vi hiện tại

| Thành phần | Phạm vi |
| --- | --- |
| Phân loại | AO/OTA **2018**, nhóm lớn A/B/C: 2R3 đầu dưới xương quay, 31 đầu trên xương đùi, 41 đầu trên xương chày; người lớn |
| Ảnh | JPEG/PNG; DICOM Part 10 đơn khung, đơn sắc, little endian không nén; HEIC chỉ khi hệ điều hành chuyển sang JPEG/PNG |
| Trình xem | Zoom/pan, xoay, cắt, đảo ảnh, độ sáng/tương phản, so sánh hai ảnh, chú thích và đo thủ công |
| Lưu trữ | AES-256-GCM trong vùng riêng ứng dụng; khóa trong kho an toàn hệ điều hành; không tự động tải ảnh lên mạng |
| Báo cáo | PDF A4, font tiếng Việt được đóng gói cục bộ; ảnh đã render và nhận xét do người dùng nhập |
| AI | Interface và tiền xử lý để tích hợp sau; không có trọng số hoặc dự đoán giả |

Chưa có phân nhóm số AO/OTA, hiệu chỉnh phối cảnh, giải mã DICOM nén/multiframe, mô hình AI đã đánh giá, hoặc chứng nhận y tế. Chất lượng ảnh chỉ có kiểm tra kỹ thuật sơ bộ. Thông số Pixel Spacing trong DICOM không tự động được xem là hiệu chuẩn đáng tin cậy. Không suy ra hướng điều trị cá thể từ mã phân loại.

## Build và cài đặt

- [Android: APK, chữ ký và cài đặt](docs/BUILD_ANDROID.md)
- [iPhone: macOS/Xcode, ký ứng dụng và TestFlight](docs/BUILD_IOS.md)
- [Kiến trúc](docs/ARCHITECTURE.md)
- [Kiểm chứng lâm sàng và giới hạn](docs/CLINICAL_VALIDATION.md)

```bash
bash scripts/build_android.sh
```

Script tạo `release/OrthoAI-Android.apk` và checksum khi build thành công. Cấu hình mặc định dùng **debug signing cho bản phát triển**, dù Dart được biên dịch ở chế độ release. Không dùng khóa debug cho bản phát hành chính thức.

IPA cho iPhone cần macOS, Xcode, Apple team, certificate và provisioning phù hợp. Source iOS được cung cấp; một file APK không chạy trên iPhone. Không đổi tên artifact Android thành IPA.

## Dữ liệu và nguồn

Không nhập tên, ngày sinh, mã hồ sơ hoặc địa chỉ người bệnh. Bản gốc có thể chứa metadata DICOM và được giữ trong ca mã hóa; ảnh hiển thị/PDF được dựng lại không sao chép metadata. Chữ định danh đã in trong điểm ảnh vẫn có thể còn: bác sĩ phải kiểm tra trước khi nhập/xuất. Xuất PDF/PNG tạo bản sao không mã hóa bên ngoài kho ca. Xóa ca không thu hồi bản đã chia sẻ; xóa ứng dụng có thể làm mất khóa/dữ liệu.

Quy tắc và liên kết nguồn nằm trong `assets/clinical_rules/ao_ota_2018.json`. Không phân phối lại hình vẽ, ảnh hoặc toàn văn AO. Ứng dụng không được AO Foundation hoặc OTA chứng thực. Các thư viện và font giữ giấy phép riêng; xem màn hình giấy phép và `assets/fonts/OFL.txt`.
