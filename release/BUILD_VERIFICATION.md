# Báo cáo bàn giao OrthoAI 0.1.0+1

Ngày: **10/11/2026 (Asia/Saigon)**. Môi trường build: Linux x86_64, Flutter **3.47.9 stable**, Dart **3.13.7**, JDK **21.0.13**. Đây là bản phát triển nghiên cứu/giáo dục, chưa được thẩm định chẩn đoán hoặc chứng nhận thiết bị y tế.

## Artifact đã xác minh

- APK: `/workspace/work/orthoai/release/OrthoAI-Android.apk`.
- Kích thước: **65.099.996 byte** (65,1 MB; khoảng 62,1 MiB).
- SHA-256: `30c6d1debb4352e4d6c89fbfc85bcd0d3df47ad88af9e8b0193c6d3165e4e2d2`.
- Package: `org.orthoai.orthoai`; versionName `0.1.0`; versionCode `1`.
- Android tối thiểu API **24**, compile/target API **36**.
- ABI: **arm64-v8a**, armeabi-v7a, x86_64. Đã kiểm tra có `lib/arm64-v8a/libapp.so` và `libflutter.so`.
- `apksigner verify`: **Verifies**, chữ ký APK v2 hợp lệ, một signer `CN=Android Debug, O=Android, C=US`. Đây là APK release về chế độ biên dịch nhưng **ký debug**, chưa phải định danh ký phát hành chính thức.
- Quyền chức năng của APK: CAMERA. Không có RECORD_AUDIO, READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE hay INTERNET trong manifest cuối. Còn một permission nội bộ cho dynamic receiver do thư viện Android tạo.
- Kiểm tra ZIP/CRC: không phát hiện mục lỗi.
- Mã nguồn được đóng gói ở `/workspace/work/orthoai/release/OrthoAI-Flutter-source.zip`; không gồm cache, SDK, dữ liệu ca, keystore hoặc thông tin ký Apple.
- **Không có `OrthoAI-iOS.ipa`.**

## Lệnh kiểm tra và kết quả thực tế

Các lệnh Flutter trong phiên dùng `source /workspace/work/tools/env.sh`. Toolchain này nằm ngoài source. Trên máy cá nhân dùng Flutter/JDK/SDK đã cấu hình bình thường; nên có ít nhất 16 GB đĩa trống cho SDK, cache và build.

| Lệnh | Kết quả |
| --- | --- |
| `flutter doctor -v` | Flutter/Android SDK được nhận, license được chấp nhận; Chrome/Linux desktop thiếu thành phần, không có macOS/Xcode. Bước kiểm tra thiết bị gặp lỗi adb muốn ghi thư mục home chỉ đọc. Không có điện thoại/emulator để kiểm thử. |
| `flutter pub get` | Thành công; phiên bản dependency khóa trong `pubspec.lock`. |
| `flutter analyze` | **No issues found**, lần cuối 15,2 giây. |
| `flutter test` | **34/34 đạt**, lần cuối 12 giây. |
| `flutter build apk --release` | Đã thực thi. Bản APK ứng dụng được sinh, nhưng lệnh tổng thể trả lỗi khi mô-đun dev `integration_test` tải AndroidX test metadata từ Google Maven: HTTP 503. Không báo lệnh này thành công. |
| `cd android && ./gradlew :app:assembleRelease -Ptarget-platform=android-arm,android-arm64,android-x64 -Ptarget=lib/main.dart` | **BUILD SUCCESSFUL in 3m 6s**, 474 actionable tasks. Đây là lệnh build cuối tạo APK bàn giao, không chạy tác vụ release của mô-đun kiểm thử không dùng trong APK. |
| `apksigner verify --verbose --print-certs release/OrthoAI-Android.apk` | Chữ ký v2 hợp lệ; chi tiết trong `verification/apk-signature.txt`. |
| `aapt dump badging release/OrthoAI-Android.apk` | Package, SDK, ABI và quyền như trên; `verification/apk-properties.txt`. |
| `ZipFile(...).testzip()` | `None`: không có mục ZIP hỏng. |
| `flutter build ios --release --no-codesign` | Đã thử trên Linux, CLI trả 64 và không chấp nhận tùy chọn của build iOS. Không có macOS/Xcode để thực hiện biên dịch iOS; đây không phải kết quả kiểm chứng mã iOS. |
| Parse `ios/Runner/Info.plist`, `ios/Flutter/AppFrameworkInfo.plist` bằng `plistlib` | Thành công. Có Xcode project/workspace, deployment target iOS 15, bundle ID và mô tả quyền. |
| `bash -n scripts/build_android.sh` | Thành công. |

Log nằm trong `docs/verification/`. Các lần build đầu gặp thiếu javac và giới hạn đĩa; đã cài JDK đầy đủ và chuyển NDK/cache công cụ tạm sang ổ RAM. Không sửa SDK Flutter hoặc thay repository Maven bằng nguồn không chính thức. Không chạy test và build native đồng thời trong cùng checkout vì chúng có thể ghi lại GeneratedPluginRegistrant cho chế độ khác nhau. CI đi kèm **được cấu hình nhưng chưa được chạy trên GitHub**.

## Luồng phần mềm đã kiểm thử

Bài kiểm thử `test/app_workflow_test.dart` dùng ảnh PNG tổng hợp, không phải phim người bệnh và không phải dữ liệu thẩm định lâm sàng:

1. Giải mã qua `ImagingService.prepare`, tạo bản hiển thị không metadata.
2. Mở `ViewerScreen`, vẽ phép đo khoảng cách bằng cử chỉ, lưu PNG có chú thích và session. Chưa hiệu chuẩn vẫn dùng pixel.
3. Nhập tuổi người lớn, bên trái và nhận xét do bác sĩ nhập.
4. Chọn đầu dưới xương quay, trả lời quan sát, thu hẹp tới 2R3A; chưa có xác nhận cho tới khi chấp nhận hộp thoại của bác sĩ.
5. Mở bảng hỗ trợ điều trị và xác minh có nút tham khảo AO với URL chính thức.
6. Tạo PDF thật có header `%PDF-` từ dữ liệu ca.
7. Lưu ca mã hóa, đọc lại và đối chiếu phân loại, lâm sàng, ảnh chú thích và session.

Các test khác bao phủ JPEG/PNG, xoay/loại EXIF, ảnh lỗi, DICOM uncompressed, pixel có dấu, MONOCHROME1, window/level, giới hạn buffer, transfer syntax không hỗ trợ, đo góc/khoảng cách/hiệu chuẩn, quy tắc xác định, mâu thuẫn, thiếu dữ liệu, mã hóa/chống sửa ciphertext, ca hỏng, tóm tắt lịch sử và PDF tiếng Việt. Một PDF thử nghiệm đã được render và kiểm tra bố cục/chữ tiếng Việt trong quá trình phát triển.

## Chức năng đã triển khai

- Giao diện tiếng Việt/Anh, sáng/tối, consent lần đầu, tổng quan, ca mới/lịch sử, xóa ca.
- Camera native có preview, đèn nếu thiết bị hỗ trợ, zoom, chụp lại; nhập ảnh/thư viện/tệp DICOM. Chưa kiểm chứng thao tác native trên điện thoại trong phiên này.
- Viewer zoom/pan, cắt, xoay, đảo ảnh, sáng/tương phản, so sánh hai ảnh, nét tự do/đường/mũi tên/vòng tròn/trục, undo/redo, khoảng cách và góc; lưu bản chú thích. Bản gốc giữ riêng trong ca mã hóa.
- DICOM Part 10 đơn sắc, đơn khung, implicit/explicit little endian không nén; window/level trên dữ liệu gốc và nhãn hướng để bác sĩ xác minh.
- AO/OTA **2018 nhóm lớn A/B/C** cho đầu dưới xương quay, đầu trên xương đùi, đầu trên xương chày; dữ liệu có nguồn và trạng thái chờ chuyên gia rà soát. Bác sĩ xác nhận riêng.
- Form lâm sàng phân biệt chưa đánh giá với bình thường; cảnh báo gãy hở, tưới máu và chèn ép khoang khi người dùng ghi nhận dấu hiệu nghi ngờ.
- Tóm tắt giáo dục có nguồn, nút mở AO Surgery Reference, PDF ngoại tuyến có font tiếng Việt, preview và chia sẻ sau consent.
- Ca lưu AES-256-GCM; khóa trong secure storage hệ điều hành; lịch sử giữ tóm tắt, nạp ảnh khi mở ca; tệp hỏng được giữ và liệt kê riêng. Cache nhập được dọn; bản xuất tạm dọn khi khởi động lại.
- Contract suy luận và tiền xử lý cho mở rộng sau. **Không có trọng số AI hoặc chẩn đoán AI.**

## Giới hạn và bước còn lại

- Chưa cài/chạy trên điện thoại hoặc emulator: cần kiểm tra camera và từ chối quyền, picker, lifecycle, hiệu năng ảnh lớn, PDF preview native, mở trình duyệt, bảng chia sẻ, lưu/mở lại sau khởi động và xóa trên Android/iPhone thật. Widget test không thay thế việc đó.
- Chưa có khóa ký phát hành Android của tổ chức. Đọc `BUILD_ANDROID.md` trước khi phát hành/cập nhật; không gỡ app chứa dữ liệu cần giữ chỉ để đổi khóa.
- Linux không thể xác nhận biên dịch iOS; cần Mac/Xcode. Đọc `BUILD_IOS.md` để chọn Team, bundle ID, certificate/profile, cài iPhone bằng Xcode và tạo IPA/TestFlight. Không có IPA chưa ký được gắn nhãn cài được.
- Google Maven HTTP 503 chặn lệnh Flutter aggregate do dependency của mô-đun test; build target ứng dụng đã thành công. Máy/CI mới vẫn cần truy cập các repository chính thức để tải dependency.
- Chưa có phân nhóm số AO/OTA, quy tắc trẻ em, mô hình AI, hiệu chỉnh phối cảnh hoặc phát hiện phản chiếu đáng tin cậy. HEIC cần OS chuyển sang JPEG/PNG. DICOM nén, đa khung, một số LUT/sequence không được hỗ trợ và sẽ bị từ chối.
- Chưa có xác thực bác sĩ, audit bất biến, đồng bộ, phục hồi khóa hoặc sao lưu do ứng dụng quản lý. iOS có thể sao lưu tệp mã hóa theo OS nhưng khóa chỉ dành cho thiết bị này. Xóa ca không thu hồi bản đã chia sẻ; xóa ứng dụng có thể làm mất dữ liệu/khóa.
- Chưa được kiểm chứng hoặc phê duyệt sử dụng chẩn đoán. Nguồn phân loại đã đối chiếu không đồng nghĩa phần mềm đã được thẩm định. Xem `CLINICAL_VALIDATION.md`.

## Cài thử Android

Chuyển APK tới Android API 24 trở lên, cho phép cài từ ứng dụng mở file, rồi chạm APK; hoặc dùng `adb install -r release/OrthoAI-Android.apk` trên máy đã kết nối thiết bị. Đây là hướng dẫn cài, **không phải tuyên bố đã kiểm thử cài trên thiết bị thật**.

Trong phiên cloud, thư mục giao file `/codex/browser/projectless/0002-files-pasted-by-the-user-uploaded-pasted-text-po/output` không tồn tại và root filesystem không cho tạo thư mục. Không có công cụ upload/đính kèm tệp được cung cấp. Các artifact thực tế được giữ trong thư mục `release/` của workspace; không tạo liên kết tải giả.
