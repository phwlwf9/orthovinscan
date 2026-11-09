# Phạm vi lâm sàng và kế hoạch kiểm chứng

## Intended use hiện tại

OrthoAI 0.1 là nguyên mẫu nghiên cứu/giáo dục dành cho nhân viên y tế có chuyên môn để ghi nhận quan sát, đo ảnh thủ công, tham khảo nhóm phân loại và đọc nguồn chuyên môn. Không phải thiết bị chẩn đoán tự động, chưa được chứng nhận hoặc kiểm chứng độ chính xác chẩn đoán. Không thay thế khám trực tiếp hoặc đánh giá chuyên khoa.

Ứng dụng không chứa mô hình AI được huấn luyện/đánh giá, không sinh xác suất bệnh, không suy diễn gãy xương từ ảnh và không tự chọn phẫu thuật. Nhãn “AI” trong tên sản phẩm không thay đổi giới hạn này.

## Knowledge base

- Hệ phân loại: **AO/OTA Fracture and Dislocation Classification Compendium, 2018**, Journal of Orthopaedic Trauma 32, Supplement 1.
- Chỉ mã nhóm lớn người lớn: **2R3A/B/C**, **31A/B/C**, **41A/B/C**; không phân nhóm số hoặc suy ra mức độ nặng hoàn chỉnh.
- Vị trí source: `assets/clinical_rules/ao_ota_2018.json`, phiên bản `1.0.0-research`; nguồn và URL trong từng rule/section, trạng thái `pending_clinician_review`.
- Các tiêu chí nhóm lớn được đối chiếu nguồn chính: S28 đầu dưới xương quay, S33 đầu trên xương đùi, S49 đầu trên xương chày. Kiểm tra nguồn/URL ngày 09/11/2026 không tương đương review lâm sàng hoặc xác nhận hiệu quả ứng dụng.
- Tóm tắt điều trị là đoạn gốc ngắn dùng cho thảo luận, liên kết nguồn AO chính thức. Không tái phân phối biểu đồ, ảnh hoặc toàn văn AO, không được AO/OTA chứng thực.

Nguồn chính: [Compendium 2018](https://media.aofoundation.org/trauma/-/media/project/aocd/aotrauma/documents/classification/aoota_classification_2018_compendium.pdf?rev=8be490d5b65f44688bd11af197bbe55e), [AO Surgery Reference](https://surgeryreference.aofoundation.org/), [OTA Core Curriculum: Fracture Classifications](https://ota.org/sites/files/2021-06/General%20A1%20Fracture%20Classifications.pdf).

## Tách nguồn thông tin

Quan sát và lâm sàng là dữ liệu do người dùng nhập, không phải phát hiện của phần mềm. Khoảng cách/góc là phép tính hình học từ điểm đặt thủ công, phụ thuộc chất lượng ảnh và hiệu chuẩn. Ứng viên AO/OTA là kết quả engine áp quy tắc lên đầu vào, chưa thành chẩn đoán. Mã chỉ có trạng thái xác nhận khi bác sĩ thực hiện thao tác xác nhận; việc phần mềm cho phép xác nhận không thay thế trách nhiệm chuyên môn.

Khi còn thiếu dữ liệu, ứng dụng không đưa kết luận chắc chắn. Trẻ em, hình ảnh chưa đủ hoặc quan sát mâu thuẫn không đủ điều kiện xác nhận bằng bộ quy tắc này. Các dấu hiệu gãy hở, thiếu máu chi và chèn ép khoang chỉ tạo nhắc nhở đánh giá khẩn.

## Giới hạn còn tồn tại

1. Chưa có nghiên cứu độ lặp lại giữa người đọc hoặc so sánh với hội đồng chuyên gia; chưa có chỉ số sensitivity/specificity hay mức đồng thuận được xác nhận.
2. Ảnh chụp màn hình/lightbox chịu méo phối cảnh, lóa và phơi sáng; không tương đương phim số gốc. Chưa có hiệu chỉnh phối cảnh. Kiểm tra blur/exposure chỉ là heuristic kỹ thuật, không chứng minh ảnh đủ chất lượng chẩn đoán.
3. DICOM chỉ nhận Part 10 đơn khung đơn sắc không nén little endian. Không hỗ trợ mọi LUT, compression, presentation state, multiframe hoặc mọi cách lồng sequence; có thể từ chối file hợp lệ nằm ngoài phạm vi. Hướng và Pixel Spacing phải được xác minh; không tự trình bày mm từ tag chưa thẩm định.
4. Phân loại ở mức nhóm lớn không đủ để quyết định chỉ định, đường mổ, implant hoặc phục hồi chức năng. Không cung cấp hướng dẫn phẫu thuật cá thể hoặc thay thế nguồn chính thức đầy đủ.
5. Mã hóa tại chỗ không bảo vệ được thiết bị đã bị chiếm quyền. PDF/PNG đã xuất và file gốc do người dùng giữ ngoài ứng dụng không nằm trong kho mã hóa. Không tự nhận diện/xóa chữ định danh in trong điểm ảnh.
6. Cần kiểm thử trên điện thoại thật, các phiên bản hệ điều hành, trường hợp quyền bị từ chối, tiến trình bị hủy, hết dung lượng, ca lớn và khôi phục khóa. Kết quả thực sự đã chạy phải xem ở `BUILD_VERIFICATION.md`.

## Trước khi sử dụng trong nghiên cứu lâm sàng hoặc chăm sóc

Cần chuyên gia chấn thương chỉnh hình review từng tiêu chí, bản dịch, tóm tắt điều trị, nguồn và mapping code; ghi người duyệt, phiên bản và ngày. Xác định protocol, phạm vi tuổi/giải phẫu, điều kiện loại trừ và thước đo an toàn trước khi thu thập dữ liệu.

Kiểm chứng hình học bằng phantom/bộ ảnh có ground truth cho distance, angle, zoom, crop/rotate và calibration; kiểm tra ảnh signed/unsigned, MONOCHROME1/2, window/level và đầu vào lỗi. Review độc lập đường xử lý dữ liệu, export consent, deletion, khóa mã hóa và metadata. Thử nghiệm usability với bác sĩ; kiểm tra người dùng phân biệt “chưa rõ”, “bình thường”, ứng viên và xác nhận.

Nếu thêm mô hình AI, phải có nguồn trọng số, giấy phép, mô tả tập huấn luyện/đánh giá, leakage checks, đánh giá ngoài cơ sở, calibration và uncertainty, subgroup/domain-shift analysis, human oversight và quản lý thay đổi. Không nâng trạng thái sang “đã thẩm định” chỉ vì test phần mềm hoặc build đã qua.
