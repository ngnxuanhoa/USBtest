# Kiểm tra laptop cũ

Script PowerShell chạy từ USB, giúp **kiểm tra nhanh tình trạng một chiếc laptop Windows cũ trước khi mua**. Script thu thập thông tin phần cứng, chấm từng mục theo ba mức **OK / CẢNH BÁO / XẤU**, rồi xuất ra một báo cáo HTML kèm kết luận cuối cùng.

Không cần cài đặt gì lên máy cần kiểm tra: cắm USB, bấm chạy, đợi vài phút.

> **Lưu ý:** đây là công cụ sàng lọc, không thay thế việc tự kiểm tra bằng mắt và tay (màn hình, bàn phím, bản lề, cổng kết nối, loa, webcam...). Xem phần [Giới hạn](#giới-hạn).

## Tính năng

| Nhóm | Nội dung kiểm tra |
|---|---|
| Hệ thống | Hãng, model, serial, BIOS, phiên bản Windows |
| Bản quyền Windows | Key OEM trong BIOS, trạng thái kích hoạt, kênh bản quyền, so khớp key đang dùng với key OEM, phát hiện dấu vết domain/chính sách công ty cũ |
| CPU, RAM, GPU | Model chip, số nhân/luồng, từng thanh RAM, driver card đồ họa, độ phân giải |
| Ổ cứng | Sức khỏe do Windows báo, giờ chạy (đổi ra ngày/tháng/năm), độ hao mòn SSD, lỗi đọc/ghi |
| SMART chi tiết *(tùy chọn)* | Tổng TB đã đọc/ghi, sector lỗi, lỗi media, nhật ký lỗi của chính ổ, hỗ trợ cả SATA và NVMe |
| Pin | Dung lượng thiết kế, dung lượng đầy hiện tại, % độ chai, số chu kỳ sạc |
| Nhật ký lỗi 90 ngày | Lỗi phần cứng (WHEA), tắt máy đột ngột, driver màn hình treo, lỗi ổ đĩa phân loại theo từng ổ, kèm giải thích cụ thể |
| Test màn hình *(tương tác)* | Hiện lần lượt các màu đen, trắng, đỏ, xanh lá, xanh dương, xám toàn màn hình để bạn quan sát điểm chết, hở sáng, ám màu |
| Test RAM nhanh *(tùy chọn)* | Ghi và đọc lại nhiều kiểu dữ liệu trên phần RAM đang trống để tìm lỗi |
| Benchmark WinSAT *(tùy chọn)* | Chấm điểm CPU, RAM, ổ cứng, đồ họa bằng công cụ có sẵn của Windows |
| Stress test CPU *(tùy chọn)* | Chạy tải nặng 3 phút, theo dõi xung nhịp để phát hiện tụt xung do nóng |

## Yêu cầu

- Windows 10 hoặc 11, Windows PowerShell 5.1 (có sẵn trong Windows)
- Quyền Administrator
- Cắm sạc nếu muốn chạy benchmark WinSAT (WinSAT không chạy khi dùng pin)

## Cách dùng

1. Tải về và chép `KiemTraLaptop.ps1` và `ChayKiemTra.bat` vào USB (đường dẫn không nên có dấu cách).
2. *(Tùy chọn)* Chuẩn bị `smartctl` như hướng dẫn ở [phần dưới](#đọc-smart-đầy-đủ-với-smartctl-tùy-chọn).
3. Cắm USB vào laptop cần kiểm tra, nhấp đúp `ChayKiemTra.bat`, chọn **Yes** khi Windows hỏi quyền Admin.
4. Trả lời 4 câu hỏi Y/N ở đầu (test màn hình, test RAM, benchmark, stress test CPU). Trả lời xong, script tự chạy phần còn lại.
5. Sau khoảng 1-12 phút (tùy các bài test đã chọn), báo cáo `BaoCao_<serial>.html` được lưu ngay trong thư mục chứa script và tự mở lên.

Cửa sổ PowerShell hiển thị **không dấu** (để tránh lỗi phông chữ trên console cũ), còn báo cáo HTML có **tiếng Việt có dấu** đầy đủ.

Cuối script có thêm lựa chọn mở **Windows Memory Diagnostic** để test toàn bộ RAM. Bước này cần khởi động lại máy, báo cáo đã được lưu trước đó.

Nếu muốn chạy trực tiếp file `.ps1`, mở PowerShell bằng quyền Admin rồi chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\KiemTraLaptop.ps1
```

### Đọc SMART đầy đủ với smartctl (tùy chọn)

Nếu có `smartctl`, script đọc thêm được tổng TB đã đọc/ghi, sector lỗi và log lỗi của ổ NVMe/SATA. Không có thì script vẫn chạy bình thường.

1. Tải smartmontools bản Windows từ trang chính thức: <https://www.smartmontools.org>
2. Giải nén file cài đặt bằng 7-Zip (hoặc cài lên máy khác rồi copy ra).
3. Lấy hai file `smartctl.exe` và `drivedb.h`, đặt vào thư mục `smartctl` cạnh script:

```
USB:\
  KiemTraLaptop.ps1
  ChayKiemTra.bat
  smartctl\
    smartctl.exe
    drivedb.h
```

smartmontools là phần mềm GPL của bên thứ ba và **không** được đóng kèm trong repo này.

## Cách chấm điểm

Các ngưỡng dưới đây do tác giả đặt ra để sàng lọc, bạn có thể sửa trực tiếp trong script cho phù hợp.

| Mục | CẢNH BÁO | XẤU |
|---|---|---|
| RAM | Dưới 8 GB | Có lỗi khi test RAM nhanh |
| Giờ chạy ổ cứng | Trên 30.000 giờ | |
| Hao mòn SSD / Percentage Used | Từ 50% | Từ 80% |
| Sector lỗi (SATA) | Từ 1 đến 9 | Từ 10 |
| Lỗi media, cảnh báo nghiêm trọng (NVMe) | | Khác 0 |
| Độ chai pin (còn lại) | 60% đến dưới 80% | Dưới 60% |
| Số chu kỳ sạc | Trên 800 | |
| Xung CPU khi tải nặng so với xung tối đa | Dưới 80% | Dưới 60% |
| Nhiệt độ (ACPI thermal zone) | Từ 80 °C | Từ 90 °C |
| WHEA, tắt máy đột ngột, driver màn hình treo | 1 đến 4 lần | Từ 5 lần |
| Lỗi nghiêm trọng trên ổ gắn trong máy | Lỗi mức cảnh báo | Lỗi mức nghiêm trọng (bad block, SMART báo sắp hỏng...) |
| Điểm WinSAT CPU, RAM | 4 đến dưới 6 | Dưới 4 |
| Điểm WinSAT ổ SSD | 5,5 đến dưới 7 | Dưới 5,5 |

**Kết luận cuối báo cáo:**

- Có ít nhất 1 mục XẤU: không nên mua, hoặc chỉ mua giá rất rẻ.
- Từ 3 mục CẢNH BÁO: cân nhắc, thương lượng giá.
- 1 đến 2 mục CẢNH BÁO: tạm ổn, kiểm tra thêm bằng mắt.
- Không có cảnh báo nào: tốt theo số liệu đọc được.

Lỗi trên ổ USB/ổ ngoài không ảnh hưởng kết luận về máy, vì script tách riêng ổ gắn trong máy và ổ ngoài.

## Giới hạn

- **Số liệu do phần cứng tự khai.** SMART của ổ cứng, dung lượng pin, số giờ chạy đều do firmware báo cáo và có thể bị chỉnh sửa. Với máy giá rẻ bất thường hoặc người bán né tránh việc kiểm tra, hãy cẩn thận hơn.
- **Máy vừa cài lại Windows** thì nhật ký lỗi bị xóa, nên phần nhật ký ít thông tin.
- **Không kiểm tra được bằng phần mềm:** điểm chết màn hình (nếu bạn bỏ qua test màn hình), bàn phím, touchpad, cổng USB/HDMI, loa, mic, webcam, Wi-Fi, bản lề, vỏ máy, khóa BIOS/MDM.
- **Nhiệt độ CPU** nhiều laptop không cho Windows đọc qua API chuẩn. Khi đó báo cáo ghi "Không đọc được"; hãy xem trong BIOS hoặc dùng công cụ như HWiNFO.
- **Test RAM nhanh** chỉ kiểm tra phần RAM đang trống. Muốn kiểm tra toàn bộ, dùng Windows Memory Diagnostic hoặc MemTest86 từ USB boot.
- **WinSAT** có thể không đọc được kết quả trên một số bản Windows 11.
- Script chưa được kiểm chứng trên nhiều dòng máy. Nếu gặp lỗi, vui lòng mở issue kèm nội dung lỗi.

## Quyền riêng tư

Báo cáo HTML chứa **serial máy** và **key Windows OEM**. Đừng đăng công khai hoặc đưa lên repo. Repo này đã chặn sẵn file `BaoCao_*.html` trong `.gitignore`.

Script chạy hoàn toàn trên máy, không gửi dữ liệu đi đâu.

## Cấu trúc dự án

```
KiemTraLaptop/
  KiemTraLaptop.ps1    Script chính
  ChayKiemTra.bat      Chạy script với quyền Admin chỉ bằng nhấp đúp
  README.md
  LICENSE
  .gitignore
  .gitattributes
```

Lưu ý khi chỉnh sửa script: file cần lưu dạng **UTF-8 có BOM** để Windows PowerShell 5.1 đọc đúng tiếng Việt có dấu.

## Đóng góp

Mọi góp ý, báo lỗi hoặc pull request đều được hoan nghênh. Nếu thêm bài kiểm tra mới, hãy giữ nguyên nguyên tắc: **chỉ đọc và kiểm tra**, không thay đổi cấu hình hay dữ liệu trên máy được kiểm tra.

## Giấy phép

Xem file [LICENSE](LICENSE).

## Cảm ơn

- [smartmontools](https://www.smartmontools.org) cho công cụ đọc SMART (tùy chọn, tải riêng).
