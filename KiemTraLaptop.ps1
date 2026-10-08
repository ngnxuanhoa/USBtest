#Requires -RunAsAdministrator
# KiemTraLaptop.ps1 - Thu thập thông tin và đánh giá laptop cũ trước khi mua
# Tùy chọn: đặt smartctl.exe (+ drivedb.h) vào thư mục "smartctl" cạnh script này để đọc SMART đầy đủ (kể cả NVMe).

$ErrorActionPreference = 'SilentlyContinue'
$rows = New-Object System.Collections.ArrayList

function Add-Row($Group, $Item, $Value, $Status = 'INFO', $Note = '') {
    [void]$rows.Add([pscustomobject]@{ Group = $Group; Item = $Item; Value = "$Value"; Status = $Status; Note = $Note })
}

# Cửa sổ PowerShell hiển thị KHÔNG DẤU (tránh lỗi font/encoding); báo cáo HTML vẫn có dấu đầy đủ.
function Vn($t) {
    $s = ([string]$t).Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Replace([string][char]0x0111, 'd').Replace([string][char]0x0110, 'D').Replace([string][char]0x00B0, '')
}
function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][object]$Object = '',
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor
    )
    $p = @{ Object = (Vn $Object) }
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $p.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $p.BackgroundColor = $BackgroundColor }
    Microsoft.PowerShell.Utility\Write-Host @p
}
function Read-Host {
    param([Parameter(Position = 0)][string]$Prompt)
    Microsoft.PowerShell.Utility\Read-Host -Prompt (Vn $Prompt)
}

# Mã hóa ký tự đặc biệt khi ghi ra HTML
function Enc($t) { return [System.Net.WebUtility]::HtmlEncode([string]$t) }
function Short-Text($t, $max = 220) {
    $line = ([string]$t -split "`r?`n")[0].Trim()
    if ($line.Length -gt $max) { $line = $line.Substring(0, $max) + '...' }
    return $line
}
function Fmt-Time($d) { return ([datetime]$d).ToString('dd/MM/yyyy HH:mm') }

# Đổi giờ chạy sang ngày / tháng / năm
function Format-Hours($h) {
    $h = [double]$h
    return ("{0:N0} giờ (~{1:N0} ngày, ~{2:N1} tháng, ~{3:N2} năm chạy liên tục)" -f $h, ($h / 24), ($h / 730), ($h / 8760))
}

# Hiện các màu đơn sắc toàn màn hình để kiểm tra điểm chết / hở sáng / ám màu
function Move-ScreenColor {
    $script:scrIdx++
    if ($script:scrIdx -ge $script:scrColors.Count) { $script:scrForm.Close() }
    else { $script:scrForm.BackColor = $script:scrColors[$script:scrIdx] }
}
function Invoke-ScreenTest {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $script:scrColors = @(
        [System.Drawing.Color]::Black,
        [System.Drawing.Color]::White,
        [System.Drawing.Color]::Red,
        [System.Drawing.Color]::FromArgb(0, 255, 0),
        [System.Drawing.Color]::FromArgb(0, 0, 255),
        [System.Drawing.Color]::FromArgb(128, 128, 128)
    )
    $script:scrIdx = 0
    $script:scrForm = New-Object System.Windows.Forms.Form
    $script:scrForm.FormBorderStyle = 'None'
    $script:scrForm.StartPosition = 'Manual'
    $script:scrForm.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $script:scrForm.TopMost = $true
    $script:scrForm.KeyPreview = $true
    $script:scrForm.BackColor = $script:scrColors[0]
    $script:scrForm.Add_Shown({ param($s, $e) $s.Activate() })
    $script:scrForm.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $s.Close() } else { Move-ScreenColor } })
    $script:scrForm.Add_MouseDown({ Move-ScreenColor })
    [System.Windows.Forms.Cursor]::Hide()
    [void]$script:scrForm.ShowDialog()
    [System.Windows.Forms.Cursor]::Show()
    $script:scrForm.Dispose()
}

function Get-ScoreStatus($score, $okMin, $warnMin) {
    if ($score -ge $okMin) { return 'OK' }
    elseif ($score -ge $warnMin) { return 'WARN' }
    else { return 'BAD' }
}

Write-Host ""
Write-Host "Chọn các bài test (Y = chạy, N = bỏ qua):" -ForegroundColor Cyan
$doScreen = Read-Host "  1) Test màn hình: hiện các màu đơn sắc toàn màn hình, bạn tự quan sát? (Y/N)"
$doRam    = Read-Host "  2) Test RAM nhanh ngay trong Windows (~1-2 phút)? (Y/N)"
$doCpu    = Read-Host "  3) Stress test CPU 3 phút (kiểm tra nóng/tụt xung)? (Y/N)"
$doBench  = Read-Host "  4) Benchmark WinSAT chấm điểm CPU/RAM/ổ cứng/đồ họa (~2-5 phút, cần cắm sạc)? (Y/N)"

Write-Host "Đang thu thập thông tin, vui lòng đợi..." -ForegroundColor Cyan

# ---------------- HỆ THỐNG ----------------
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$g = 'Hệ thống'
Add-Row $g 'Hãng / Model' "$($cs.Manufacturer) $($cs.Model)"
Add-Row $g 'Serial' $bios.SerialNumber 'INFO' 'Đối chiếu serial trên trang bảo hành của hãng'
Add-Row $g 'BIOS' "$($bios.SMBIOSBIOSVersion) - $($bios.ReleaseDate)"
Add-Row $g 'Windows' "$($os.Caption) $($os.OSArchitecture)"

# Key Windows đi kèm máy (OA3.0, nằm trong BIOS) và trạng thái kích hoạt hiện tại
$sls = Get-CimInstance SoftwareLicensingService
$oemKey = $sls.OA3xOriginalProductKey
if ($oemKey) {
    Add-Row $g 'Key Windows OEM (hãng cài trong BIOS)' $oemKey 'INFO' 'Key đi theo máy từ nhà sản xuất. Không chia sẻ báo cáo này công khai'
    if ($sls.OA3xOriginalProductKeyDescription) { Add-Row $g 'Loại key OEM' $sls.OA3xOriginalProductKeyDescription 'INFO' 'Cho biết key OEM dành cho bản Windows nào (Home/Pro...)' }
} else {
    Add-Row $g 'Key Windows OEM (hãng cài trong BIOS)' 'Không có' 'WARN' 'Máy không có key OEM trong BIOS: có thể máy tự ráp, thay bo mạch, hoặc Windows không đi kèm máy'
}
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
if ($lic) {
    $statusMap = @{ 0 = 'Chưa kích hoạt'; 1 = 'Đã kích hoạt (Licensed)'; 2 = 'Đang trong thời gian chờ (OOB grace)'; 3 = 'Đang trong thời gian chờ (OOT grace)'; 4 = 'Non-genuine grace'; 5 = 'Thông báo (Notification)'; 6 = 'Extended grace' }
    $stText = $statusMap[[int]$lic.LicenseStatus]
    Add-Row $g 'Trạng thái kích hoạt' $stText $(if ($lic.LicenseStatus -eq 1) { 'OK' } else { 'BAD' })
    $chanNote = ''
    $chanSt = 'INFO'
    if ($lic.Description -match 'KMS|TIMEBASED|GVLK') { $chanSt = 'WARN'; $chanNote = 'Kích hoạt kiểu KMS/có thời hạn: máy doanh nghiệp hoặc công cụ crack, cần kiểm tra kỹ' }
    Add-Row $g 'Kênh bản quyền đang dùng' $lic.Description $chanSt $chanNote
    if ($oemKey -and $oemKey.EndsWith($lic.PartialProductKey)) {
        Add-Row $g 'Key đang dùng (5 ký tự cuối)' $lic.PartialProductKey 'OK' 'Trùng với key OEM trong BIOS: đang dùng key đi theo máy'
    } else {
        Add-Row $g 'Key đang dùng (5 ký tự cuối)' $lic.PartialProductKey 'INFO' 'Khác key OEM trong BIOS: có thể chủ cũ đã đổi key Retail riêng. Chạy slmgr /ipk [key OEM] rồi slmgr /ato để thử kích hoạt bằng key OEM'
    }
} else {
    Add-Row $g 'Trạng thái kích hoạt' 'Không đọc được giấy phép' 'BAD'
}
if ($cs.PartOfDomain) {
    Add-Row $g 'Domain / quản lý doanh nghiệp' "Đang join domain: $($cs.Domain)" 'WARN' 'Máy còn thuộc domain công ty cũ: nên rời domain hoặc Reset this PC'
}
$wuPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
if ($wuPolicy) {
    $wuNote = 'Có chính sách Windows Update của tổ chức còn sót lại (hay hiện dòng "managed by your organization")'
    if ($wuPolicy.WUServer) { $wuNote += " - WSUS: $($wuPolicy.WUServer)" }
    Add-Row $g 'Chính sách Windows Update' 'Đang bị quản lý' 'WARN' $wuNote
}

# ---------------- CPU ----------------
$g = 'CPU'
foreach ($c in Get-CimInstance Win32_Processor) {
    Add-Row $g 'Chip' $c.Name 'INFO' 'Đối chiếu với thông số người bán quảng cáo'
    Add-Row $g 'Nhân / Luồng' "$($c.NumberOfCores) nhân / $($c.NumberOfLogicalProcessors) luồng"
    Add-Row $g 'Xung tối đa' "$($c.MaxClockSpeed) MHz"
}

# ---------------- RAM ----------------
$g = 'RAM'
$sticks = Get-CimInstance Win32_PhysicalMemory
$totalGB = [math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB)
Add-Row $g 'Tổng dung lượng' "$totalGB GB" $(if ($totalGB -lt 8) { 'WARN' } else { 'OK' }) 'Dưới 8GB sẽ chậm với Windows hiện nay'
foreach ($s in $sticks) {
    Add-Row $g "Thanh RAM ($($s.DeviceLocator))" ("{0} GB - {1} MHz - {2}" -f [math]::Round($s.Capacity / 1GB), $s.Speed, $s.Manufacturer)
}
if ($doRam -match '^[Yy]') {
    $ramCode = @'
using System;
public static class RamTester {
    public static int TestedMB;
    public static long Errors;
    public static void Run(int targetMB) {
        int chunkMB = 64;
        int n = targetMB / chunkMB;
        int len = chunkMB * 1024 * 1024 / 8;
        ulong[][] chunks = new ulong[n][];
        int allocated = 0;
        try { for (int i = 0; i < n; i++) { chunks[i] = new ulong[len]; allocated++; } }
        catch (OutOfMemoryException) { }
        TestedMB = allocated * chunkMB;
        Errors = 0;
        ulong[] pats = new ulong[] { 0x0000000000000000UL, 0xFFFFFFFFFFFFFFFFUL, 0xAAAAAAAAAAAAAAAAUL, 0x5555555555555555UL };
        unchecked {
            foreach (ulong pat in pats) {
                for (int c = 0; c < allocated; c++) { ulong[] a = chunks[c]; for (int j = 0; j < a.Length; j++) a[j] = pat; }
                for (int c = 0; c < allocated; c++) { ulong[] a = chunks[c]; for (int j = 0; j < a.Length; j++) if (a[j] != pat) Errors++; }
            }
            ulong mul = 0x9E3779B97F4A7C15UL;
            for (int c = 0; c < allocated; c++) { ulong[] a = chunks[c]; for (int j = 0; j < a.Length; j++) a[j] = ((ulong)c * (ulong)len + (ulong)j) * mul; }
            for (int c = 0; c < allocated; c++) { ulong[] a = chunks[c]; for (int j = 0; j < a.Length; j++) if (a[j] != (((ulong)c * (ulong)len + (ulong)j) * mul)) Errors++; }
        }
    }
}
'@
    if (-not ('RamTester' -as [type])) { Add-Type -TypeDefinition $ramCode }
    $freeMB = [int]([math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024))
    $targetMB = [math]::Min([int]($freeMB * 0.7), 6144)
    if (-not [Environment]::Is64BitProcess) { $targetMB = [math]::Min($targetMB, 1024) }
    $targetMB = [int]([math]::Floor($targetMB / 64) * 64)
    if ($targetMB -lt 256) {
        Add-Row $g 'Test RAM nhanh' 'Không đủ RAM trống để test' 'INFO' 'Đóng bớt ứng dụng rồi chạy lại, hoặc dùng mdsched / MemTest86'
    } else {
        Write-Host "Đang test RAM (~$targetMB MB), vui lòng đợi..." -ForegroundColor Yellow
        $t0 = Get-Date
        [RamTester]::Run($targetMB)
        $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds)
        $errs = [RamTester]::Errors
        $pctTested = [math]::Round([RamTester]::TestedMB / ($totalGB * 1024) * 100)
        Add-Row $g 'Test RAM nhanh (trong Windows)' "Đã test $([RamTester]::TestedMB) MB (~$pctTested % tổng RAM) trong $secs giây, $errs lỗi" $(if ($errs -eq 0) { 'OK' } else { 'BAD' }) 'Chỉ test phần RAM đang trống. Để test toàn bộ RAM hãy dùng mdsched (cuối script) hoặc MemTest86 từ USB boot'
    }
} else {
    Add-Row $g 'Kiểm tra lỗi RAM' 'Bỏ qua' 'INFO' 'Chạy lại script và chọn Y, hoặc dùng mdsched / MemTest86'
}

# ---------------- GPU / MÀN HÌNH ----------------
$g = 'Card đồ họa / Màn hình'
foreach ($v in Get-CimInstance Win32_VideoController) {
    $st = if ($v.Status -eq 'OK') { 'OK' } else { 'WARN' }
    Add-Row $g "GPU: $($v.Name)" ("Driver {0} - Độ phân giải {1}x{2} - {3} Hz" -f $v.DriverVersion, $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution, $v.CurrentRefreshRate) $st
}
if ($doScreen -match '^[Yy]') {
    Write-Host ""
    Write-Host "Màn hình sẽ hiện lần lượt các màu: đen, trắng, đỏ, xanh lá, xanh dương, xám." -ForegroundColor Yellow
    Write-Host "Bấm chuột hoặc phím bất kỳ để đổi màu, ESC để thoát sớm." -ForegroundColor Yellow
    Write-Host "Quan sát kỹ cả 4 góc và viền: điểm chết (chấm đen trên nền sáng), điểm kẹt (chấm sáng), hở sáng ở viền khi nền đen, ám màu / vệt mây khi nền trắng và xám, sọc ngang/dọc, nhấp nháy." -ForegroundColor Yellow
    [void](Read-Host "Chỉnh độ sáng màn hình lên cao, tắt đèn phòng nếu được. Nhấn Enter để bắt đầu")
    Invoke-ScreenTest
    $scrAns = Read-Host "Bạn có thấy lỗi nào trên màn hình không? (Y = có lỗi / N = không thấy lỗi)"
    if ($scrAns -match '^[Yy]') {
        $scrDetail = Read-Host "Mô tả ngắn lỗi đã thấy (Enter để bỏ qua)"
        Add-Row $g 'Test màn hình (quan sát bằng mắt)' "Có lỗi: $scrDetail" 'WARN' 'Người kiểm tra báo có lỗi, cần đánh giá mức độ hoặc thương lượng giá'
    } else {
        Add-Row $g 'Test màn hình (quan sát bằng mắt)' 'Không thấy lỗi' 'OK' 'Do người kiểm tra tự quan sát (đen/trắng/đỏ/xanh lá/xanh dương/xám)'
    }
} else {
    Add-Row $g 'Màn hình (điểm chết, hở sáng, ám màu)' 'Chưa test' 'INFO' 'Chạy lại script và chọn Y để hiện các màu đơn sắc toàn màn hình'
}

# ---------------- Ổ CỨNG ----------------
foreach ($d in Get-PhysicalDisk) {
    $g = "Ổ cứng: $($d.FriendlyName)"
    Add-Row $g 'Loại / Dung lượng' ("{0} {1} - {2} GB" -f $d.MediaType, $d.BusType, [math]::Round($d.Size / 1GB))
    Add-Row $g 'Windows báo sức khỏe' $d.HealthStatus $(if ($d.HealthStatus -eq 'Healthy') { 'OK' } else { 'BAD' })
    $rc = $d | Get-StorageReliabilityCounter
    if ($rc) {
        if ($null -ne $rc.PowerOnHours) {
            $h = [int]$rc.PowerOnHours
            $st = if ($h -gt 30000) { 'WARN' } else { 'OK' }
            Add-Row $g 'Giờ chạy' (Format-Hours $h) $st 'Giờ chạy thấp bất thường so với vẻ ngoài máy cũ là đáng ngờ'
        }
        if ($null -ne $rc.Wear) {
            $w = [int]$rc.Wear
            $st = if ($w -ge 80) { 'BAD' } elseif ($w -ge 50) { 'WARN' } else { 'OK' }
            Add-Row $g 'Độ hao mòn (SSD)' "$w %" $st
        }
        if ($null -ne $rc.ReadErrorsUncorrected -and $rc.ReadErrorsUncorrected -gt 0) { Add-Row $g 'Lỗi đọc không sửa được' $rc.ReadErrorsUncorrected 'BAD' }
        if ($null -ne $rc.WriteErrorsUncorrected -and $rc.WriteErrorsUncorrected -gt 0) { Add-Row $g 'Lỗi ghi không sửa được' $rc.WriteErrorsUncorrected 'BAD' }
        if ($null -ne $rc.Temperature) { Add-Row $g 'Nhiệt độ' "$($rc.Temperature) °C" $(if ($rc.Temperature -ge 60) { 'WARN' } else { 'OK' }) }
    }
}

# ---------------- SMART CHI TIẾT (smartctl portable, tùy chọn) ----------------
$smart = Join-Path $PSScriptRoot 'smartctl\smartctl.exe'
if (Test-Path $smart) {
    $scan = (& $smart --scan -j) -join "`n" | ConvertFrom-Json
    foreach ($dev in $scan.devices) {
        $j = (& $smart -a -j -d $dev.type $dev.name) -join "`n" | ConvertFrom-Json
        if (-not $j) { continue }
        $g = "SMART: $($j.model_name) [$($dev.name)]"
        if ($null -ne $j.smart_status.passed) {
            Add-Row $g 'SMART tổng quát' $(if ($j.smart_status.passed) { 'PASSED' } else { 'FAILED' }) $(if ($j.smart_status.passed) { 'OK' } else { 'BAD' })
        }
        if ($null -ne $j.power_on_time.hours) { Add-Row $g 'Giờ chạy (SMART)' (Format-Hours $j.power_on_time.hours) }
        if ($null -ne $j.power_cycle_count) { Add-Row $g 'Số lần bật nguồn' $j.power_cycle_count }
        if ($j.ata_smart_error_log) {
            $ec = [int]$j.ata_smart_error_log.summary.count
            Add-Row $g 'Nhật ký lỗi SMART (ATA error log)' $ec $(if ($ec -eq 0) { 'OK' } else { 'WARN' }) 'Số lỗi mà ổ từng tự ghi lại trong bộ nhớ của nó. Khác 0 là ổ từng gặp lỗi đọc/ghi; xem chi tiết bằng: smartctl -l error /dev/sdX'
        }

        # SATA
        if ($j.ata_smart_attributes) {
            foreach ($a in @(@(5, 'Sector chuyển vùng (Reallocated)'), @(197, 'Sector chờ xử lý (Pending)'), @(198, 'Sector không sửa được'))) {
                $attr = $j.ata_smart_attributes.table | Where-Object { $_.id -eq $a[0] }
                if ($attr) {
                    $raw = [int64]$attr.raw.value
                    $st = if ($raw -eq 0) { 'OK' } elseif ($raw -lt 10) { 'WARN' } else { 'BAD' }
                    Add-Row $g $a[1] $raw $st 'Khác 0 là dấu hiệu xuống cấp'
                }
            }
        }
        # NVMe
        $n = $j.nvme_smart_health_information_log
        if ($n) {
            $pu = [int]$n.percentage_used
            Add-Row $g 'Đã dùng (Percentage Used)' "$pu %" $(if ($pu -ge 80) { 'BAD' } elseif ($pu -ge 50) { 'WARN' } else { 'OK' })
            $tb = [math]::Round(([double]$n.data_units_written * 512000) / 1e12, 1)
            Add-Row $g 'Tổng đã ghi' "$tb TB"
            $tbr = [math]::Round(([double]$n.data_units_read * 512000) / 1e12, 1)
            Add-Row $g 'Tổng đã đọc' "$tbr TB"
            Add-Row $g 'Lỗi media' $n.media_errors $(if ($n.media_errors -gt 0) { 'BAD' } else { 'OK' })
            Add-Row $g 'Cảnh báo nghiêm trọng' $n.critical_warning $(if ($n.critical_warning -ne 0) { 'BAD' } else { 'OK' })
            Add-Row $g 'Tắt nguồn đột ngột' $n.unsafe_shutdowns
            if ($null -ne $n.num_err_log_entries) { Add-Row $g 'Số mục trong error log của ổ (NVMe)' $n.num_err_log_entries 'INFO' 'Số lớn không hẳn là xấu, nhiều ổ vẫn ghi nhận mục nhẹ; xem chi tiết bằng: smartctl -l error /dev/nvme0' }
        }
    }
} else {
    Add-Row 'SMART chi tiết' 'smartctl.exe' 'Không tìm thấy' 'INFO' 'Chép smartctl.exe vào thư mục smartctl cạnh script để đọc thêm TB đọc/ghi và SMART đầy đủ'
}

# ---------------- BENCHMARK (WinSAT) ----------------
$g = 'Benchmark (WinSAT)'
if ($doBench -match '^[Yy]') {
    $bt = Get-CimInstance Win32_Battery
    $onBattery = [bool]($bt | Where-Object { $_.BatteryStatus -eq 1 })
    if ($onBattery) {
        Add-Row $g 'Benchmark' 'Bỏ qua: máy đang dùng pin' 'INFO' 'Cắm sạc rồi chạy lại script, WinSAT không chạy khi dùng pin'
    } else {
        Write-Host "Đang chạy benchmark WinSAT (khoảng 2-5 phút), vui lòng đợi..." -ForegroundColor Yellow
        Start-Process -FilePath "$env:windir\System32\winsat.exe" -ArgumentList 'formal', '-restart', 'clean' -Wait -NoNewWindow | Out-Null
        $ws = Get-CimInstance Win32_WinSAT
        if ($ws -and $ws.WinSATAssessmentState -eq 1) {
            $hasSsd = [bool](Get-PhysicalDisk | Where-Object MediaType -eq 'SSD')
            $cpuS = [double]$ws.CPUScore
            $memS = [double]$ws.MemoryScore
            $dskS = [double]$ws.DiskScore
            $gfxS = [double]$ws.GraphicsScore
            $d3dS = [double]$ws.D3DScore
            Add-Row $g 'Điểm CPU' ("{0:N1} / 9.9" -f $cpuS) (Get-ScoreStatus $cpuS 6 4) 'So với máy cùng dòng chip: thấp bất thường thường do tản nhiệt kém hoặc bị giới hạn công suất'
            Add-Row $g 'Điểm RAM' ("{0:N1} / 9.9" -f $memS) (Get-ScoreStatus $memS 6 4) 'Thấp có thể do RAM chạy đơn kênh hoặc tốc độ thấp'
            if ($hasSsd) {
                Add-Row $g 'Điểm ổ cứng' ("{0:N1} / 9.9" -f $dskS) (Get-ScoreStatus $dskS 7 5.5) 'SSD khỏe thường trên 7; thấp hơn là ổ chậm hoặc xuống cấp'
            } else {
                Add-Row $g 'Điểm ổ cứng' ("{0:N1} / 9.9" -f $dskS) (Get-ScoreStatus $dskS 5 4) 'Ổ HDD thường ~5-6; dưới 4 là rất chậm'
            }
            Add-Row $g 'Điểm đồ họa (giao diện)' ("{0:N1} / 9.9" -f $gfxS) $(if ($gfxS -lt 3) { 'WARN' } else { 'INFO' }) 'Card onboard điểm trung bình là bình thường'
            Add-Row $g 'Điểm đồ họa (3D / game)' ("{0:N1} / 9.9" -f $d3dS) 'INFO' 'Chỉ có ý nghĩa khi so với máy cùng card'
            Add-Row $g 'Lưu ý khi đọc điểm' 'Điểm chỉ có ý nghĩa khi so với máy cùng dòng chip' 'INFO' 'Chạy khi cắm sạc, chế độ hiệu năng cao. Tra điểm WinSAT / Cinebench của cùng chip trên mạng để đối chiếu'
        } else {
            Add-Row $g 'Benchmark' 'Không lấy được kết quả WinSAT' 'INFO' 'WinSAT có thể không chạy được trên máy này (vd một số bản Windows 11); thử Cinebench hoặc CrystalDiskMark'
        }
    }
} else {
    Add-Row $g 'Benchmark' 'Bỏ qua' 'INFO' 'Chạy lại script và chọn Y để chấm điểm CPU/RAM/ổ cứng'
}

# ---------------- STRESS TEST CPU ----------------
$g = 'Stress test CPU'
$ans = $doCpu
if ($ans -match '^[Yy]') {
    $durationSec = 180
    $coreCount = [int]$env:NUMBER_OF_PROCESSORS
    Add-Row $g 'Số luồng chạy' "$coreCount tiến trình, $durationSec giây"

    # Ghi nhận xung nhịp trước test (máy đang idle)
    Start-Sleep -Seconds 2
    $idleClock = (Get-CimInstance Win32_Processor | Measure-Object CurrentClockSpeed -Average).Average
    $maxClock  = (Get-CimInstance Win32_Processor | Measure-Object MaxClockSpeed -Average).Average
    Add-Row $g 'Xung khi không tải' "$([math]::Round($idleClock)) MHz (tối đa $([math]::Round($maxClock)) MHz)"

    # Tạo tải nặng trên tất cả nhân
    $jobs = 1..$coreCount | ForEach-Object {
        Start-Job -ScriptBlock {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $using:durationSec) {
                $x = 0.0001
                1..200000 | ForEach-Object { $x = [math]::Sqrt($x) * 1.0000001 }
            }
        }
    }

    Write-Host "Đang chạy tải nặng CPU trong $durationSec giây, vui lòng đợi..." -ForegroundColor Yellow
    $samples = New-Object System.Collections.ArrayList
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $durationSec) {
        Start-Sleep -Seconds 5
        $clk = (Get-CimInstance Win32_Processor | Measure-Object CurrentClockSpeed -Average).Average
        $load = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
        [void]$samples.Add([pscustomobject]@{ T = [math]::Round($sw.Elapsed.TotalSeconds); Clock = [math]::Round($clk); Load = [math]::Round($load) })
        Write-Host ("  {0,3}s  xung: {1,5} MHz  tải: {2,3}%" -f [math]::Round($sw.Elapsed.TotalSeconds), [math]::Round($clk), [math]::Round($load))
    }
    Wait-Job -Job $jobs | Out-Null
    $jobs | Remove-Job -Force

    $minClock = ($samples | Measure-Object Clock -Minimum).Minimum
    $avgClockLoad = ($samples | Where-Object Load -gt 80 | Measure-Object Clock -Average).Average
    if (-not $avgClockLoad) { $avgClockLoad = ($samples | Measure-Object Clock -Average).Average }
    $avgLoad = ($samples | Measure-Object Load -Average).Average

    Add-Row $g 'Tải CPU trung bình khi test' "$([math]::Round($avgLoad)) %" $(if ($avgLoad -lt 70) { 'WARN' } else { 'OK' }) 'Nếu quá thấp, tải chưa đủ nặng để phản ánh đúng'
    Add-Row $g 'Xung thấp nhất ghi nhận' "$([math]::Round($minClock)) MHz"
    Add-Row $g 'Xung trung bình khi tải nặng' "$([math]::Round($avgClockLoad)) MHz"

    if ($maxClock -gt 0) {
        $pct = $avgClockLoad / $maxClock * 100
        $st = if ($pct -lt 60) { 'BAD' } elseif ($pct -lt 80) { 'WARN' } else { 'OK' }
        Add-Row $g 'So với xung tối đa' "$([math]::Round($pct)) %" $st 'Dưới 80% khi tải nặng liên tục là dấu hiệu giảm xung do nóng (throttling) hoặc giới hạn điện'
    }

    # Kiểm tra Event Log xem có lỗi/tắt máy bất thường trong lúc test không
    $testStart = (Get-Date).AddSeconds(-$durationSec - 10)
    $kpDuring = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $testStart }).Count
    Add-Row $g 'Tắt máy đột ngột trong lúc test' $kpDuring $(if ($kpDuring -eq 0) { 'OK' } else { 'BAD' })

    # Lưu ý về nhiệt độ: Windows không có API nhiệt độ CPU chuẩn cho mọi máy
    $thermal = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature
    if ($thermal) {
        foreach ($t in $thermal) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            if ($celsius -gt 0 -and $celsius -lt 120) {
                $st = if ($celsius -ge 90) { 'BAD' } elseif ($celsius -ge 80) { 'WARN' } else { 'OK' }
                Add-Row $g 'Nhiệt độ ACPI thermal zone' "$celsius °C" $st
            }
        }
    } else {
        Add-Row $g 'Nhiệt độ CPU' 'Không đọc được' 'INFO' 'Windows không có sẵn API nhiệt độ đáng tin cậy trên nhiều laptop; nếu cần chính xác hãy dùng HWiNFO hoặc xem BIOS sau khi test'
    }
} else {
    Add-Row $g 'Stress test CPU' 'Bỏ qua' 'INFO' 'Chạy lại script và chọn Y nếu muốn kiểm tra'
}

# ---------------- PIN ----------------
$g = 'Pin'
$xmlPath = Join-Path $env:TEMP 'batt-report.xml'
Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
powercfg /batteryreport /xml /output $xmlPath | Out-Null
if (Test-Path $xmlPath) {
    [xml]$x = Get-Content $xmlPath -Raw
    $batts = $x.SelectNodes("//*[local-name()='Batteries']/*[local-name()='Battery']")
    if ($batts.Count -eq 0) {
        Add-Row $g 'Pin' 'Không phát hiện pin' 'WARN' 'Máy bàn hoặc pin tạo/không nhận'
    }
    foreach ($b in $batts) {
        $design = [double]$b.SelectSingleNode("*[local-name()='DesignCapacity']").InnerText
        $full   = [double]$b.SelectSingleNode("*[local-name()='FullChargeCapacity']").InnerText
        $cyc    = $b.SelectSingleNode("*[local-name()='CycleCount']").InnerText
        if ($design -gt 0) {
            $pct = [math]::Round($full / $design * 100)
            $st = if ($pct -ge 80) { 'OK' } elseif ($pct -ge 60) { 'WARN' } else { 'BAD' }
            Add-Row $g 'Dung lượng thiết kế' "$design mWh"
            Add-Row $g 'Dung lượng đầy hiện tại' "$full mWh"
            Add-Row $g 'Độ chai (còn lại)' "$pct %" $st 'Dưới 60% nên tính thêm tiền thay pin'
        }
        if ($cyc) { Add-Row $g 'Số chu kỳ sạc' $cyc $(if ([int]$cyc -gt 800) { 'WARN' } else { 'OK' }) }
    }
} else {
    Add-Row $g 'Báo cáo pin' 'Không tạo được' 'INFO' 'Máy có thể là desktop hoặc không có pin'
}

# ---------------- NHẬT KÝ LỖI PHẦN CỨNG (90 ngày) ----------------
$g = 'Nhật ký lỗi (90 ngày gần đây)'
$since = (Get-Date).AddDays(-90)

# ---- WHEA / Kernel-Power / Display: đếm + thời điểm + nội dung cụ thể ----
$wheaEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since })
$kpEv   = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since })
$dispEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $since })

$note = ''
if ($wheaEv.Count -gt 0) {
    $lastW = $wheaEv | Sort-Object TimeCreated | Select-Object -Last 1
    $note = "Gần nhất: $(Fmt-Time $lastW.TimeCreated). Nội dung gốc: $(Short-Text $lastW.Message)"
}
Add-Row $g 'Lỗi phần cứng WHEA (CPU/RAM/bus)' $wheaEv.Count $(if ($wheaEv.Count -eq 0) { 'OK' } elseif ($wheaEv.Count -lt 5) { 'WARN' } else { 'BAD' }) $note

$note = 'Nhiều thường do quá nhiệt hoặc lỗi nguồn/pin'
if ($kpEv.Count -gt 0) {
    $lastK = $kpEv | Sort-Object TimeCreated | Select-Object -Last 1
    $bug = $null
    try { $bug = $lastK.Properties[0].Value } catch { }
    $bugText = ''
    if ($null -ne $bug) {
        if ([int64]$bug -eq 0) { $bugText = ' Mã BugcheckCode = 0: máy mất điện đột ngột hoặc bị giữ nút nguồn, không phải màn hình xanh.' }
        else { $bugText = " Mã BugcheckCode = 0x{0:X}: tắt do lỗi hệ thống (màn hình xanh)." -f [int64]$bug }
    }
    $note = "Gần nhất: $(Fmt-Time $lastK.TimeCreated).$bugText Nhiều lần thường do quá nhiệt, lỗi nguồn/pin hoặc pin yếu."
}
Add-Row $g 'Tắt máy đột ngột (Kernel-Power 41)' $kpEv.Count $(if ($kpEv.Count -eq 0) { 'OK' } elseif ($kpEv.Count -lt 5) { 'WARN' } else { 'BAD' }) $note

$note = 'Driver card đồ họa bị treo rồi tự hồi phục'
if ($dispEv.Count -gt 0) {
    $lastD = $dispEv | Sort-Object TimeCreated | Select-Object -Last 1
    $note = "Gần nhất: $(Fmt-Time $lastD.TimeCreated). Driver card đồ họa bị treo rồi tự hồi phục; nhiều lần là dấu hiệu lỗi driver hoặc card."
}
Add-Row $g 'Driver màn hình bị treo (Display 4101)' $dispEv.Count $(if ($dispEv.Count -eq 0) { 'OK' } elseif ($dispEv.Count -lt 5) { 'WARN' } else { 'BAD' }) $note

# ---- Lỗi ổ đĩa / lưu trữ: phân loại theo từng ổ và giải thích cụ thể ----
# Mỗi mục: Tên lỗi | Mức độ | Ý nghĩa | Cách xử lý
$evCatalog = @{
    'disk:7'       = @('Bad block (khối hỏng trên ổ)', 'BAD', 'Ổ phát hiện khối (block) hỏng khi đọc hoặc ghi.', 'Sao lưu dữ liệu ngay, kiểm tra SMART và quét bề mặt. Nếu là ổ trong máy thì nghi ổ hỏng.')
    'disk:9'       = @('Ổ không phản hồi trong thời gian chờ (timeout)', 'WARN', 'Thao tác đọc/ghi bị hết thời gian chờ.', 'Thường do cáp/cổng USB chập chờn hoặc ổ đang bị lỗi. Với ổ trong máy cần theo dõi và kiểm tra SMART.')
    'disk:11'      = @('Lỗi bộ điều khiển ổ (controller error)', 'WARN', 'Bộ điều khiển, cáp hoặc cổng kết nối báo lỗi.', 'Kiểm tra cáp và cổng. Với ổ trong máy, nghi mạch điều khiển hoặc ổ.')
    'disk:15'      = @('Ổ chưa sẵn sàng truy cập', 'WARN', 'Ổ tạm thời không sẵn sàng (mất kết nối, ngủ sâu, đang khởi động lại).', 'Với ổ USB thường do tiết kiệm điện; với ổ trong máy nên theo dõi thêm.')
    'disk:51'      = @('Lỗi khi đọc/ghi bộ nhớ ảo (paging error)', 'WARN', 'Windows gặp lỗi khi đọc/ghi dữ liệu bộ nhớ trên ổ. Hay xảy ra khi ổ bị mất kết nối lúc đang chạy chương trình từ ổ đó, hoặc cáp/cổng chập chờn, hoặc ổ lỗi.', 'Với ổ USB: rút đúng cách (Eject), đổi cáp/cổng. Với ổ trong máy: kiểm tra SMART và quét bề mặt ngay.')
    'disk:52'      = @('Ổ dự đoán sắp hỏng (SMART)', 'BAD', 'Ổ tự báo hiệu sắp hỏng theo SMART.', 'Sao lưu dữ liệu ngay và thay ổ.')
    'disk:153'     = @('Thao tác đọc/ghi phải thử lại', 'WARN', 'Đọc/ghi không thành công lần đầu, phải thử lại.', 'Thường do cáp/cổng chập chờn hoặc ổ chậm; nhiều lần trên ổ trong máy là dấu hiệu xuống cấp.')
    'disk:154'     = @('Thao tác đọc/ghi thất bại do lỗi phần cứng', 'BAD', 'Ổ báo lỗi phần cứng khi đọc/ghi.', 'Sao lưu dữ liệu, kiểm tra SMART; với ổ trong máy nên thay.')
    'disk:157'     = @('Ổ bị rút đột ngột (không bấm Eject)', 'INFO', 'Ổ bị gỡ ra khi chưa được ngắt an toàn.', 'Không phải lỗi ổ, chỉ là rút USB/ổ ngoài đột ngột.')
    'Ntfs:55'      = @('Hệ thống tệp bị hỏng cấu trúc', 'BAD', 'Windows phát hiện hỏng cấu trúc hệ thống tệp trên một phân vùng.', 'Sao lưu trước, rồi chạy chkdsk /f cho phân vùng đó (thêm /r để quét bề mặt).')
    'stornvme:129' = @('Bộ điều khiển NVMe bị reset', 'WARN', 'Bộ điều khiển phải reset vì ổ không phản hồi kịp.', 'Nhiều lần trên ổ trong máy là dấu hiệu ổ hoặc firmware có vấn đề; cập nhật firmware và kiểm tra SMART.')
    'storahci:129' = @('Bộ điều khiển SATA/AHCI bị reset', 'WARN', 'Bộ điều khiển phải reset vì ổ không phản hồi kịp.', 'Nhiều lần trên ổ trong máy là dấu hiệu cáp, ổ hoặc nguồn có vấn đề; kiểm tra SMART.')
}

$diskMap = @{}
foreach ($dk in Get-Disk) { $diskMap[[int]$dk.Number] = $dk }

$storEvents = @()
foreach ($pn in @('disk', 'Ntfs', 'Microsoft-Windows-Ntfs', 'stornvme', 'storahci')) {
    $storEvents += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $pn; StartTime = $since })
}

$groups = @{}
foreach ($ev in $storEvents) {
    $prov = [string]$ev.ProviderName
    if ($prov -like '*Ntfs') { $prov = 'Ntfs' }
    $ck = "${prov}:$($ev.Id)"
    if (-not $evCatalog.ContainsKey($ck)) { continue }
    $msg = [string]$ev.Message
    $kind = 'internal'
    $label = 'Bộ điều khiển / phân vùng (xem nội dung gốc)'
    if ($prov -eq 'disk') {
        $num = $null
        if ($msg -match 'Harddisk(\d+)') { $num = [int]$Matches[1] }
        if ($null -ne $num -and $diskMap.ContainsKey($num)) {
            $dk = $diskMap[$num]
            $label = "Harddisk$num ($($dk.BusType): $($dk.FriendlyName))"
            if ($dk.BusType -eq 'USB') { $kind = 'usb' }
        } elseif ($null -ne $num) {
            $label = "Harddisk$num (hiện không còn kết nối)"
            $kind = 'gone'
        } else {
            $label = 'Không xác định được ổ'
            $kind = 'unknown'
        }
    }
    $gk = "$ck|$label"
    if (-not $groups.ContainsKey($gk)) {
        $groups[$gk] = [pscustomobject]@{
            Key = $ck; Label = $label; Kind = $kind; Count = 0
            Times = (New-Object System.Collections.ArrayList); Sample = (Short-Text $msg)
        }
    }
    $o = $groups[$gk]
    $o.Count++
    [void]$o.Times.Add($ev.TimeCreated)
}

# Tổng hợp cho ổ gắn trong máy (bỏ qua ổ USB và sự kiện rút ổ)
$intBad = 0; $intWarn = 0; $intEvents = 0
foreach ($o in $groups.Values) {
    if ($o.Kind -ne 'internal') { continue }
    $sev = $evCatalog[$o.Key][1]
    $intEvents += $o.Count
    if ($sev -eq 'BAD') { $intBad++ } elseif ($sev -eq 'WARN') { $intWarn++ }
}
$sumSt = if ($intBad -gt 0) { 'BAD' } elseif ($intWarn -gt 0) { 'WARN' } else { 'OK' }
$sumNote = 'Tổng hợp sự kiện lỗi ổ đĩa/lưu trữ trên ổ gắn trong máy (bỏ qua ổ USB và sự kiện rút ổ). Chi tiết từng lỗi ở bên dưới.'
if ($intEvents -eq 0) { $sumNote = 'Không có sự kiện lỗi ổ đĩa nghiêm trọng trên ổ trong máy trong 90 ngày.' }
Add-Row $g 'Lỗi ổ đĩa / lưu trữ - ổ trong máy' "$intEvents sự kiện" $sumSt $sumNote

# Chi tiết từng lỗi: tên lỗi, ổ nào, bao nhiêu lần, bao nhiêu đợt, khi nào, nội dung gốc
foreach ($gk in ($groups.Keys | Sort-Object)) {
    $o = $groups[$gk]
    $cat = $evCatalog[$o.Key]
    $times = @($o.Times | Sort-Object)
    $bursts = 1
    for ($i = 1; $i -lt $times.Count; $i++) {
        if (($times[$i] - $times[$i - 1]).TotalSeconds -gt 120) { $bursts++ }
    }
    $value = "{0} sự kiện trong {1} đợt (lần đầu {2}, gần nhất {3})" -f $o.Count, $bursts, (Fmt-Time $times[0]), (Fmt-Time $times[$times.Count - 1])
    $st = 'INFO'
    $kindNote = ''
    switch ($o.Kind) {
        'internal' { $st = $cat[1] }
        'usb'      { $st = 'INFO'; $kindNote = ' Đây là ổ USB/ngoài nên không ảnh hưởng kết luận về máy.' }
        'gone'     { $st = 'INFO'; $kindNote = ' Ổ này hiện không còn kết nối (thường là USB đã rút).' }
        'unknown'  { $st = 'WARN'; $kindNote = ' Không xác định được ổ nào.' }
    }
    $detailNote = "Ý nghĩa: $($cat[2]) Cách xử lý: $($cat[3])$kindNote Nội dung gốc: $($o.Sample)"
    Add-Row $g "$($cat[0]) - $($o.Label) [$($o.Key)]" $value $st $detailNote
}
Add-Row $g 'Xem thêm chi tiết' 'Get-WinEvent -FilterHashtable @{LogName=''System''; ProviderName=''disk''} | Select TimeCreated, Id, Message | Format-List' 'INFO' 'Chạy trong PowerShell (Admin) để xem từng sự kiện. Số thứ tự ổ (Harddisk N) có thể đổi theo thời điểm cắm/rút.'
Add-Row $g 'Lưu ý' 'Máy mới cài lại Windows thì nhật ký bị xóa nên ít thông tin' 'INFO'

# ---------------- KẾT LUẬN ----------------
$bad  = @($rows | Where-Object Status -eq 'BAD').Count
$warn = @($rows | Where-Object Status -eq 'WARN').Count
if     ($bad -ge 1)  { $verdict = "KHÔNG NÊN MUA (hoặc chỉ mua giá rất rẻ): có $bad mục XẤU, $warn mục cảnh báo"; $vcol = '#c0392b' }
elseif ($warn -ge 3) { $verdict = "CÂN NHẮC / THƯƠNG LƯỢNG GIÁ: có $warn mục cảnh báo"; $vcol = '#d68910' }
elseif ($warn -ge 1) { $verdict = "TẠM ỔN: có $warn mục cảnh báo nhỏ, kiểm tra thêm bằng mắt"; $vcol = '#7d8c00' }
else                 { $verdict = "TỐT theo số liệu đọc được (vẫn phải kiểm tra màn hình, bàn phím, cổng kết nối bằng mắt)"; $vcol = '#1e8449' }

# ---------------- XUẤT BÁO CÁO ----------------
$colors = @{ OK = '#d5f5e3'; WARN = '#fcf3cf'; BAD = '#f5b7b1'; INFO = '#ffffff' }
$label  = @{ OK = 'OK'; WARN = 'CẢNH BÁO'; BAD = 'XẤU'; INFO = '' }
$html = New-Object System.Text.StringBuilder
[void]$html.AppendLine('<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8"><title>Báo cáo kiểm tra laptop</title>')
[void]$html.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;max-width:960px}table{border-collapse:collapse;width:100%;margin-bottom:18px}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left;font-size:14px;vertical-align:top}th{background:#eee}h3{margin:18px 0 6px}.v{padding:14px;color:#fff;font-size:18px;font-weight:bold;border-radius:6px}</style></head><body>')
[void]$html.AppendLine("<h2>Báo cáo kiểm tra laptop - $(Get-Date -Format 'dd/MM/yyyy HH:mm')</h2>")
[void]$html.AppendLine("<div class='v' style='background:$vcol'>$(Enc $verdict)</div>")
foreach ($grp in ($rows | Group-Object Group)) {
    [void]$html.AppendLine("<h3>$(Enc $grp.Name)</h3><table><tr><th style='width:30%'>Mục</th><th style='width:32%'>Giá trị</th><th style='width:10%'>Đánh giá</th><th>Ghi chú</th></tr>")
    foreach ($r in $grp.Group) {
        [void]$html.AppendLine("<tr style='background:$($colors[$r.Status])'><td>$(Enc $r.Item)</td><td>$(Enc $r.Value)</td><td>$($label[$r.Status])</td><td>$(Enc $r.Note)</td></tr>")
    }
    [void]$html.AppendLine('</table>')
}
[void]$html.AppendLine('<p><b>Chưa kiểm tra được bằng phần mềm:</b> màn hình (điểm chết, nếu chưa tự test), bàn phím, touchpad, cổng USB/HDMI, loa, mic, webcam, Wi-Fi, bản lề, vỏ máy, tình trạng khóa BIOS/MDM. Các chỉ số trên do firmware tự khai nên có thể bị chỉnh sửa; hãy kết hợp test thực tế.</p></body></html>')

$serial = ($bios.SerialNumber -replace '[^\w-]', '')
$out = Join-Path $PSScriptRoot "BaoCao_$serial.html"
$html.ToString() | Set-Content -Path $out -Encoding UTF8

# ---------------- IN RA MÀN HÌNH ----------------
Write-Host ""
foreach ($grp in ($rows | Group-Object Group)) {
    Write-Host "== $($grp.Name)" -ForegroundColor Cyan
    foreach ($r in $grp.Group) {
        $col = switch ($r.Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'BAD' { 'Red' } default { 'Gray' } }
        Write-Host ("  [{0,-8}] {1}: {2}" -f $label[$r.Status], $r.Item, $r.Value) -ForegroundColor $col
    }
}
Write-Host ""
Write-Host "KẾT LUẬN: $verdict" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "Đã lưu báo cáo: $out" -ForegroundColor Cyan
Start-Process $out
$md = Read-Host "Mở Windows Memory Diagnostic để test TOÀN BỘ RAM? (cần khởi động lại máy, mất 10-30 phút; báo cáo đã lưu ở trên) (Y/N)"
if ($md -match '^[Yy]') { Start-Process mdsched.exe }
[void](Read-Host "Nhấn Enter để thoát")
