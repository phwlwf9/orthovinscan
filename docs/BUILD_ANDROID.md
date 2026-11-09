# Build Android và cài APK

## Yêu cầu

- Flutter 3.47.9 stable / Dart 3.13.7; dùng `pubspec.lock` đi kèm.
- JDK 21 trong môi trường build này; project đặt mức tương thích Java 17.
- Android SDK platform 36, build-tools 36.0.0, platform-tools, NDK 28.2.13676358; Gradle 9.3.1 / Android Gradle Plugin 9.1 trong scaffold này.
- Android từ API 24 (Android 7.0); mục tiêu API 36. Ứng dụng có ARM64; APK mặc định là universal.
- Application ID: `org.orthoai.orthoai`.

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
flutter analyze
flutter test
bash scripts/build_android.sh
```

Script chạy build release, xác nhận APK tồn tại, sao chép vào `release/OrthoAI-Android.apk` và tạo `release/OrthoAI-Android.apk.sha256`. Đầu ra gốc Flutter là `build/app/outputs/flutter-apk/app-release.apk`.

## Chữ ký của MVP

Trong `android/app/build.gradle.kts`, build type `release` dùng khóa trong `android/key.properties` nếu tệp đó tồn tại; nếu không, dùng khóa debug. APK của phiên này là **APK phát triển ký bằng khóa debug**, cài trực tiếp được khi hệ điều hành cho phép. Không phải chữ ký phát hành/Play Store. Khóa debug có thể khác giữa máy và CI: không đảm bảo cập nhật đè được APK từ lần build khác.

Kiểm tra chứng thư và nội dung:

```bash
apksigner verify --verbose --print-certs release/OrthoAI-Android.apk
unzip -l release/OrthoAI-Android.apk
sha256sum release/OrthoAI-Android.apk
```

Trên macOS có thể thay lệnh checksum bằng `shasum -a 256`. Đừng coi việc build thành công là bằng chứng kiểm chứng trên thiết bị thực hoặc chẩn đoán y tế.

## Cài trực tiếp

Chuyển APK tới điện thoại, cho phép “cài ứng dụng không rõ nguồn gốc” cho ứng dụng mở file rồi chạm APK, hoặc dùng USB debugging:

```bash
adb devices
adb install -r release/OrthoAI-Android.apk
```

Nếu báo xung đột chữ ký, dùng đúng khóa cũ để cập nhật. Gỡ ứng dụng sẽ làm mất dữ liệu và có thể mất khóa; chỉ gỡ sau khi đã chủ động xử lý dữ liệu cần giữ.

Kiểm tra thủ công trên thiết bị: mở app/consent, cấp hoặc từ chối camera, chụp/retake, nhập file lỗi và file hợp lệ, AP/nghiêng, zoom/crop/chú thích/đo, xác nhận phân loại, khởi động lại mở ca đã lưu, PDF/chia sẻ, xóa ca và dark mode. Không đưa ảnh người bệnh thật vào quy trình kiểm thử chưa được phê duyệt.

## Chữ ký phát hành chính thức

1. Chọn application ID của tổ chức trước khi phát hành. ID mặc định là định danh phát triển, không phải tài khoản/nhãn hiệu đã được đăng ký.
2. Tạo và bảo vệ keystore ngoài repository, ví dụ bằng `keytool -genkeypair -v -keystore /secure/path/orthoai-upload.jks -keyalg RSA -keysize 3072 -validity 10000 -alias orthoai-upload`. Nhập mật khẩu qua prompt; không ghi vào source hoặc lịch sử shell.
3. Tạo `android/key.properties` riêng, không theo dõi trong Git. Các trường cần thiết là `storeFile` (đường dẫn tuyệt đối tới keystore), `storePassword`, `keyAlias`, `keyPassword`. Gradle đã tự chọn signingConfig `release` khi tệp này tồn tại và báo lỗi nếu thiếu trường. Không commit keystore, mật khẩu hoặc file properties; trên CI cung cấp tệp từ secret manager trong job được bảo vệ rồi xóa sau job.
4. Lưu khóa/phục hồi theo chính sách tổ chức. Build lại, xác minh chứng thư bằng `apksigner`, thử cập nhật trên thiết bị kiểm thử rồi mới phân phối.

CI đi kèm chỉ tạo APK phát triển với chữ ký debug. Bản upload Play Store thường dùng `flutter build appbundle --release` với signing đã cấu hình và quy trình công bố phù hợp.
