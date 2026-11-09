# iPhone: Xcode, ký ứng dụng và TestFlight

Source có project native `ios/Runner.xcworkspace`, bundle ID `org.orthoai.orthoai`, deployment target iOS 15.0 và mô tả quyền camera/thư viện ảnh. **Phiên phát triển Linux không có macOS/Xcode hay thông tin ký Apple; không tạo hoặc xác nhận IPA cài được.** Kết quả thực tế được ghi riêng trong `BUILD_VERIFICATION.md`.

## Chuẩn bị trên Mac

1. Cài Flutter 3.47.9 stable và Xcode tương thích theo `flutter doctor -v`; cài command-line tools và nền tảng iOS trong Xcode.
2. Chạy các lệnh dưới đây từ thư mục source; nếu Flutter yêu cầu CocoaPods cho dependency, cài bằng phương pháp được hỗ trợ trên máy Mac rồi chạy lại. Không dùng `sudo flutter`.

```bash
xcode-select -p
xcodebuild -version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

`--no-codesign` chỉ kiểm tra build; sản phẩm chưa ký **không cài được lên iPhone thật**. CI macOS thực hiện bước kiểm tra này, không tạo IPA giả hoặc đổi tên `.app` thành `.ipa`.

## Cài lên iPhone bằng Xcode

1. Trong Xcode > Settings > Accounts, đăng nhập Apple ID hoặc team của tổ chức.
2. Chọn target **Runner** > Signing & Capabilities. Chọn Team, bật Automatically manage signing; đặt Bundle Identifier riêng thuộc quyền quản lý nếu ID mặc định không đăng ký được.
3. Kết nối iPhone, tin cậy máy, bật Developer Mode khi được yêu cầu. Chọn thiết bị thật làm run destination.
4. Xcode tạo/chọn Apple Development certificate và development provisioning profile có thiết bị phù hợp. Chọn Product > Run hoặc chạy `flutter run -d <device-id>` sau khi signing đã hoạt động.
5. Nếu dùng Apple ID miễn phí, hạn chế Personal Team/thời hạn profile vẫn áp dụng. Phải làm mới chữ ký khi cần. Không coi đây là phân phối TestFlight.

## Tạo IPA Development / Ad Hoc

Cần certificate có private key, provisioning profile đúng team/bundle ID/entitlement và danh sách thiết bị hợp lệ. Dùng Xcode Product > Archive > Distribute App, chọn phương thức phù hợp với profile và export IPA. Tên phương thức trong UI thay đổi theo phiên bản Xcode; không chọn App Store Connect cho việc sideload Ad Hoc.

Để build bằng CLI sau khi Xcode đã ký thành công, lấy `ExportOptions.plist` từ lần export hợp lệ của Xcode và dùng:

```bash
flutter build ipa --release --export-options-plist=/secure/path/ExportOptions.plist
mkdir -p release
cp build/ios/ipa/*.ipa release/OrthoAI-iOS.ipa
shasum -a 256 release/OrthoAI-iOS.ipa
```

Chỉ sao chép sau khi xác định đúng IPA được ký; nếu có nhiều file trong `build/ios/ipa`, chọn một file cụ thể thay cho wildcard. Certificate, private key, mật khẩu và provisioning profile phải ở ngoài source control. Không gửi bí mật ký qua chat.

## TestFlight

1. Cần tư cách Apple Developer Program phù hợp, app record trong App Store Connect và bundle ID duy nhất. Khai báo đúng privacy, quyền truy cập, thông tin mã hóa và intended use; người phát hành cần tự đánh giá yêu cầu quản lý phần mềm y tế.
2. Tăng build number trong `pubspec.yaml` cho mỗi lần upload. Trong Xcode Archive > Distribute App > App Store Connect, dùng Apple Distribution signing và profile đúng app.
3. Có thể dùng `flutter build ipa --release --export-options-plist=...` với export options do Xcode tạo cho App Store Connect, rồi upload bằng Organizer hoặc Transporter.
4. Chờ xử lý và hoàn tất các yêu cầu App Store Connect. Thêm internal testers hoặc gửi beta review khi cần external testing. Người thử cài qua TestFlight sau khi được mời.

IPA App Store/TestFlight không phải file sideload tự do cho mọi iPhone. Không có một chữ ký dùng được cho mọi phương thức phân phối.

## CI có chữ ký sau này

Workflow hiện tại **chỉ build iOS không ký** trên macOS. Khi tổ chức đã chọn phương thức phân phối, thêm job được chạy chủ động và được bảo vệ bằng GitHub Environment. Lưu P12/private key, mật khẩu, provisioning profile và App Store Connect API key trong secret manager; import vào keychain tạm, build với export options khớp profile, xóa keychain/profile sau job. Không bật signed upload chỉ bằng một cờ nếu signing assets chưa được cấu hình. Dùng tài khoản/khóa riêng cho CI và phân quyền theo nhu cầu.
