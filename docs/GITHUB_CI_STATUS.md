# Bàn giao GitHub và trạng thái CI

Cập nhật ngày **10/11/2026 (Asia/Saigon)**.

## Tệp đã bàn giao

Mã nguồn ứng dụng và gói cài Android đã được đẩy lên `phwlwf9/orthovinscan`, nhánh `main`. Commit bàn giao mã ứng dụng: `3bcaee60cb9360341dbd4f420b885f6e2d78c7d9`.

Đã tải lại cả APK và ZIP mã nguồn từ GitHub và đối chiếu SHA-256 với bản gốc:

| Tệp | Kích thước | SHA-256 |
| --- | ---: | --- |
| `release/OrthoAI-Android.apk` | 65.099.996 byte | `30c6d1debb4352e4d6c89fbfc85bcd0d3df47ad88af9e8b0193c6d3165e4e2d2` |
| `release/OrthoAI-Flutter-source.zip` | 783.015 byte | `54a7e72f74c20c0641b6674c10107f43ba24fb20d2bd4770a0ec0fde218307e7` |

APK là bản phát triển ký debug; không có IPA trong gói. Kết quả build Android cục bộ và 34 bài kiểm thử được ghi trong [BUILD_VERIFICATION.md](BUILD_VERIFICATION.md). Các log đó là bằng chứng của lần kiểm thử/build cục bộ, không phải kết quả GitHub Actions.

## GitHub Actions

Hai workflow được kích hoạt khi đẩy mã nguồn và đã được yêu cầu chạy lại một lần. Ở **attempt 2**, cả hai kết thúc với `failure`, danh sách jobs rỗng và trang run hiển thị thông báo của GitHub:

- [Android development APK](https://github.com/phwlwf9/orthovinscan/actions/runs/42671253279): `Internal server error. Correlation ID: a2c39147-b0ce-4123-a952-ab7d9c53abc4`.
- [iOS unsigned compilation](https://github.com/phwlwf9/orthovinscan/actions/runs/42671252902): `Internal server error. Correlation ID: 751d11b1-cc33-4940-9349-b44b89ea8602`.

Chưa có job hoặc log biên dịch từ hai run này. Vì vậy **chưa thể xác nhận biên dịch iOS trên macOS bằng CI**, và không gọi CI Android là thành công. Thông báo này không làm thay đổi file APK đã build và kiểm tra tại workspace.

Có thể chạy lại workflow sau khi sự cố GitHub được giải quyết, hoặc dùng máy Mac/Xcode theo [BUILD_IOS.md](BUILD_IOS.md). IPA cài được vẫn cần certificate và provisioning phù hợp; hướng dẫn ký và TestFlight nằm trong tài liệu đó.

Commit cập nhật báo cáo chỉ thay tài liệu, giữ nguyên mã ứng dụng và artifact. CI được bỏ qua cho commit tài liệu này để tránh lặp lại cùng lỗi dịch vụ.
