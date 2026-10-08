#Requires -RunAsAdministrator
# KiemTraLaptop.ps1 - Thu thap thong tin va danh gia laptop cu truoc khi mua
# Tuy chon: dat smartctl.exe (+ drivedb.h) vao thu muc "smartctl" canh script nay de doc SMART day du (ke ca NVMe).

$ErrorActionPreference = 'SilentlyContinue'
$rows = New-Object System.Collections.ArrayList

function Add-Row($Group, $Item, $Value, $Status = 'INFO', $Note = '') {
    [void]$rows.Add([pscustomobject]@{ Group = $Group; Item = $Item; Value = "$Value"; Status = $Status; Note = $Note })
}

# Doi gio chay sang ngay / thang / nam
function Format-Hours($h) {
    $h = [double]$h
    return ("{0:N0} gio (~{1:N0} ngay, ~{2:N1} thang, ~{3:N2} nam chay lien tuc)" -f $h, ($h / 24), ($h / 730), ($h / 8760))
}

# Hien cac mau don sac toan man hinh de kiem tra diem chet / ham sang / am mau
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
Write-Host "Chon cac bai test (Y = chay, N = bo qua):" -ForegroundColor Cyan
$doScreen = Read-Host "  1) Test man hinh: hien cac mau don sac toan man hinh, ban tu quan sat? (Y/N)"
$doRam    = Read-Host "  2) Test RAM nhanh ngay trong Windows (~1-2 phut)? (Y/N)"
$doCpu    = Read-Host "  3) Stress test CPU 3 phut (kiem tra nong/tut xung)? (Y/N)"
$doBench  = Read-Host "  4) Benchmark WinSAT cham diem CPU/RAM/o cung/do hoa (~2-5 phut, can cam sac)? (Y/N)"

Write-Host "Dang thu thap thong tin, vui long doi..." -ForegroundColor Cyan

# ---------------- HE THONG ----------------
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$g = 'He thong'
Add-Row $g 'Hang / Model' "$($cs.Manufacturer) $($cs.Model)"
Add-Row $g 'Serial' $bios.SerialNumber '' 'Doi chieu serial tren trang bao hanh cua hang'
Add-Row $g 'BIOS' "$($bios.SMBIOSBIOSVersion) - $($bios.ReleaseDate)"
Add-Row $g 'Windows' "$($os.Caption) $($os.OSArchitecture)"

# Key Windows di kem may (OA3.0, nam trong BIOS) va trang thai kich hoat hien tai
$sls = Get-CimInstance SoftwareLicensingService
$oemKey = $sls.OA3xOriginalProductKey
if ($oemKey) {
    Add-Row $g 'Key Windows OEM (hang cai trong BIOS)' $oemKey 'INFO' 'Key di theo may tu nha san xuat. Khong chia se bao cao nay cong khai'
    if ($sls.OA3xOriginalProductKeyDescription) { Add-Row $g 'Loai key OEM' $sls.OA3xOriginalProductKeyDescription 'INFO' 'Cho biet key OEM danh cho ban Windows nao (Home/Pro...)' }
} else {
    Add-Row $g 'Key Windows OEM (hang cai trong BIOS)' 'Khong co' 'WARN' 'May khong co key OEM trong BIOS: co the may tu rap, thay bo mach, hoac Windows khong di kem may'
}
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
if ($lic) {
    $statusMap = @{ 0 = 'Chua kich hoat'; 1 = 'Da kich hoat (Licensed)'; 2 = 'Dang trong thoi gian cho (OOB grace)'; 3 = 'Dang trong thoi gian cho (OOT grace)'; 4 = 'Non-genuine grace'; 5 = 'Thong bao (Notification)'; 6 = 'Extended grace' }
    $stText = $statusMap[[int]$lic.LicenseStatus]
    Add-Row $g 'Trang thai kich hoat' $stText $(if ($lic.LicenseStatus -eq 1) { 'OK' } else { 'BAD' })
    $chanNote = ''
    $chanSt = 'INFO'
    if ($lic.Description -match 'KMS|TIMEBASED|GVLK') { $chanSt = 'WARN'; $chanNote = 'Kich hoat kieu KMS/co thoi han: may doanh nghiep hoac cong cu crack, can kiem tra ky' }
    Add-Row $g 'Kenh ban quyen dang dung' $lic.Description $chanSt $chanNote
    if ($oemKey -and $oemKey.EndsWith($lic.PartialProductKey)) {
        Add-Row $g 'Key dang dung (5 ky tu cuoi)' $lic.PartialProductKey 'OK' 'Trung voi key OEM trong BIOS: dang dung key di theo may'
    } else {
        Add-Row $g 'Key dang dung (5 ky tu cuoi)' $lic.PartialProductKey 'INFO' 'Khac key OEM trong BIOS: co the chu cu da doi key Retail rieng; chay slmgr /ipk <key OEM> roi slmgr /ato de thu kich hoat bang key OEM'
    }
} else {
    Add-Row $g 'Trang thai kich hoat' 'Khong doc duoc giay phep' 'BAD'
}
if ($cs.PartOfDomain) {
    Add-Row $g 'Domain / quan ly doanh nghiep' "Dang join domain: $($cs.Domain)" 'WARN' 'May con thuoc domain cong ty cu: nen roi domain hoac Reset this PC'
}
$wuPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
if ($wuPolicy) {
    $wuNote = 'Co chinh sach Windows Update cua to chuc con sot lai (hay hien dong "managed by your organization")'
    if ($wuPolicy.WUServer) { $wuNote += " - WSUS: $($wuPolicy.WUServer)" }
    Add-Row $g 'Chinh sach Windows Update' 'Dang bi quan ly' 'WARN' $wuNote
}

# ---------------- CPU ----------------
$g = 'CPU'
foreach ($c in Get-CimInstance Win32_Processor) {
    Add-Row $g 'Chip' $c.Name 'INFO' 'Doi chieu voi thong so nguoi ban quang cao'
    Add-Row $g 'Nhan / Luong' "$($c.NumberOfCores) nhan / $($c.NumberOfLogicalProcessors) luong"
    Add-Row $g 'Xung toi da' "$($c.MaxClockSpeed) MHz"
}

# ---------------- RAM ----------------
$g = 'RAM'
$sticks = Get-CimInstance Win32_PhysicalMemory
$totalGB = [math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB)
Add-Row $g 'Tong dung luong' "$totalGB GB" $(if ($totalGB -lt 8) { 'WARN' } else { 'OK' }) 'Duoi 8GB se cham voi Windows hien nay'
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
        Add-Row $g 'Test RAM nhanh' 'Khong du RAM trong de test' 'INFO' 'Dong bot ung dung roi chay lai, hoac dung mdsched / MemTest86'
    } else {
        Write-Host "Dang test RAM (~$targetMB MB), vui long doi..." -ForegroundColor Yellow
        $t0 = Get-Date
        [RamTester]::Run($targetMB)
        $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds)
        $errs = [RamTester]::Errors
        $pctTested = [math]::Round([RamTester]::TestedMB / ($totalGB * 1024) * 100)
        Add-Row $g 'Test RAM nhanh (trong Windows)' "Da test $([RamTester]::TestedMB) MB (~$pctTested % tong RAM) trong $secs giay, $errs loi" $(if ($errs -eq 0) { 'OK' } else { 'BAD' }) 'Chi test phan RAM dang trong. De test toan bo RAM hay dung mdsched (cuoi script) hoac MemTest86 tu USB boot'
    }
} else {
    Add-Row $g 'Kiem tra loi RAM' 'Bo qua' 'INFO' 'Chay lai script va chon Y, hoac dung mdsched / MemTest86'
}

# ---------------- GPU / MAN HINH ----------------
$g = 'Card do hoa / Man hinh'
foreach ($v in Get-CimInstance Win32_VideoController) {
    $st = if ($v.Status -eq 'OK') { 'OK' } else { 'WARN' }
    Add-Row $g "GPU: $($v.Name)" ("Driver {0} - Do phan giai {1}x{2} - {3} Hz" -f $v.DriverVersion, $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution, $v.CurrentRefreshRate) $st
}
if ($doScreen -match '^[Yy]') {
    Write-Host ""
    Write-Host "Man hinh se hien lan luot cac mau: den, trang, do, xanh la, xanh duong, xam." -ForegroundColor Yellow
    Write-Host "Bam chuot hoac phim bat ky de doi mau, ESC de thoat som." -ForegroundColor Yellow
    Write-Host "Quan sat ky ca 4 goc va vien: diem chet (cham den tren nen sang), diem ket (cham sang), ham sang o vien khi nen den, am mau / vet may khi nen trang va xam, soc ngang/doc, nhap nhay." -ForegroundColor Yellow
    [void](Read-Host "Chinh do sang man hinh len cao, tat den phong neu duoc. Nhan Enter de bat dau")
    Invoke-ScreenTest
    $scrAns = Read-Host "Ban co thay loi nao tren man hinh khong? (Y = co loi / N = khong thay loi)"
    if ($scrAns -match '^[Yy]') {
        $scrDetail = [System.Net.WebUtility]::HtmlEncode((Read-Host "Mo ta ngan loi da thay (Enter de bo qua)"))
        Add-Row $g 'Test man hinh (quan sat bang mat)' "Co loi: $scrDetail" 'WARN' 'Nguoi kiem tra bao co loi, can danh gia muc do hoac thuong luong gia'
    } else {
        Add-Row $g 'Test man hinh (quan sat bang mat)' 'Khong thay loi' 'OK' 'Do nguoi kiem tra tu quan sat (den/trang/do/xanh la/xanh duong/xam)'
    }
} else {
    Add-Row $g 'Man hinh (diem chet, ham sang, am mau)' 'Chua test' 'INFO' 'Chay lai script va chon Y de hien cac mau don sac toan man hinh'
}

# ---------------- O CUNG ----------------
foreach ($d in Get-PhysicalDisk) {
    $g = "O cung: $($d.FriendlyName)"
    Add-Row $g 'Loai / Dung luong' ("{0} {1} - {2} GB" -f $d.MediaType, $d.BusType, [math]::Round($d.Size / 1GB))
    Add-Row $g 'Windows bao suc khoe' $d.HealthStatus $(if ($d.HealthStatus -eq 'Healthy') { 'OK' } else { 'BAD' })
    $rc = $d | Get-StorageReliabilityCounter
    if ($rc) {
        if ($null -ne $rc.PowerOnHours) {
            $h = [int]$rc.PowerOnHours
            $st = if ($h -gt 30000) { 'WARN' } else { 'OK' }
            Add-Row $g 'Gio chay' (Format-Hours $h) $st 'Gio chay thap bat thuong so voi ve ngoai may cu la dang ngo'
        }
        if ($null -ne $rc.Wear) {
            $w = [int]$rc.Wear
            $st = if ($w -ge 80) { 'BAD' } elseif ($w -ge 50) { 'WARN' } else { 'OK' }
            Add-Row $g 'Do hao mon (SSD)' "$w %" $st
        }
        if ($null -ne $rc.ReadErrorsUncorrected -and $rc.ReadErrorsUncorrected -gt 0) { Add-Row $g 'Loi doc khong sua duoc' $rc.ReadErrorsUncorrected 'BAD' }
        if ($null -ne $rc.WriteErrorsUncorrected -and $rc.WriteErrorsUncorrected -gt 0) { Add-Row $g 'Loi ghi khong sua duoc' $rc.WriteErrorsUncorrected 'BAD' }
        if ($null -ne $rc.Temperature) { Add-Row $g 'Nhiet do' "$($rc.Temperature) C" $(if ($rc.Temperature -ge 60) { 'WARN' } else { 'OK' }) }
    }
}

# ---------------- SMART CHI TIET (smartctl portable, tuy chon) ----------------
$smart = Join-Path $PSScriptRoot 'smartctl\smartctl.exe'
if (Test-Path $smart) {
    $scan = (& $smart --scan -j) -join "`n" | ConvertFrom-Json
    foreach ($dev in $scan.devices) {
        $j = (& $smart -a -j -d $dev.type $dev.name) -join "`n" | ConvertFrom-Json
        if (-not $j) { continue }
        $g = "SMART: $($j.model_name) [$($dev.name)]"
        if ($null -ne $j.smart_status.passed) {
            Add-Row $g 'SMART tong quat' $(if ($j.smart_status.passed) { 'PASSED' } else { 'FAILED' }) $(if ($j.smart_status.passed) { 'OK' } else { 'BAD' })
        }
        if ($null -ne $j.power_on_time.hours) { Add-Row $g 'Gio chay (SMART)' (Format-Hours $j.power_on_time.hours) }
        if ($null -ne $j.power_cycle_count) { Add-Row $g 'So lan bat nguon' $j.power_cycle_count }
        if ($j.ata_smart_error_log) {
            $ec = [int]$j.ata_smart_error_log.summary.count
            Add-Row $g 'Nhat ky loi SMART (ATA error log)' $ec $(if ($ec -eq 0) { 'OK' } else { 'WARN' }) 'So loi ma o tung tu ghi lai trong bo nho cua no. Khac 0 la o tung gap loi doc/ghi; xem chi tiet bang: smartctl -l error /dev/sdX'
        }

        # SATA
        if ($j.ata_smart_attributes) {
            foreach ($a in @(@(5, 'Sector chuyen vung (Reallocated)'), @(197, 'Sector cho xu ly (Pending)'), @(198, 'Sector khong sua duoc'))) {
                $attr = $j.ata_smart_attributes.table | Where-Object { $_.id -eq $a[0] }
                if ($attr) {
                    $raw = [int64]$attr.raw.value
                    $st = if ($raw -eq 0) { 'OK' } elseif ($raw -lt 10) { 'WARN' } else { 'BAD' }
                    Add-Row $g $a[1] $raw $st 'Khac 0 la dau hieu xuong cap'
                }
            }
        }
        # NVMe
        $n = $j.nvme_smart_health_information_log
        if ($n) {
            $pu = [int]$n.percentage_used
            Add-Row $g 'Da dung (Percentage Used)' "$pu %" $(if ($pu -ge 80) { 'BAD' } elseif ($pu -ge 50) { 'WARN' } else { 'OK' })
            $tb = [math]::Round(([double]$n.data_units_written * 512000) / 1e12, 1)
            Add-Row $g 'Tong da ghi' "$tb TB"
            $tbr = [math]::Round(([double]$n.data_units_read * 512000) / 1e12, 1)
            Add-Row $g 'Tong da doc' "$tbr TB"
            Add-Row $g 'Loi media' $n.media_errors $(if ($n.media_errors -gt 0) { 'BAD' } else { 'OK' })
            Add-Row $g 'Canh bao nghiem trong' $n.critical_warning $(if ($n.critical_warning -ne 0) { 'BAD' } else { 'OK' })
            Add-Row $g 'Tat nguon dot ngot' $n.unsafe_shutdowns
            if ($null -ne $n.num_err_log_entries) { Add-Row $g 'So muc trong error log cua o (NVMe)' $n.num_err_log_entries 'INFO' 'So lon khong han la xau, nhieu o van ghi nhan muc nhe; xem chi tiet bang: smartctl -l error /dev/nvme0' }
        }
    }
} else {
    Add-Row 'SMART chi tiet' 'smartctl.exe' 'Khong tim thay' 'INFO' 'Chep smartctl.exe vao thu muc smartctl canh script de doc them TB doc/ghi va SMART day du'
}

# ---------------- BENCHMARK (WinSAT) ----------------
$g = 'Benchmark (WinSAT)'
if ($doBench -match '^[Yy]') {
    $bt = Get-CimInstance Win32_Battery
    $onBattery = [bool]($bt | Where-Object { $_.BatteryStatus -eq 1 })
    if ($onBattery) {
        Add-Row $g 'Benchmark' 'Bo qua: may dang dung pin' 'INFO' 'Cam sac roi chay lai script, WinSAT khong chay khi dung pin'
    } else {
        Write-Host "Dang chay benchmark WinSAT (khoang 2-5 phut), vui long doi..." -ForegroundColor Yellow
        Start-Process -FilePath "$env:windir\System32\winsat.exe" -ArgumentList 'formal', '-restart', 'clean' -Wait -NoNewWindow | Out-Null
        $ws = Get-CimInstance Win32_WinSAT
        if ($ws -and $ws.WinSATAssessmentState -eq 1) {
            $hasSsd = [bool](Get-PhysicalDisk | Where-Object MediaType -eq 'SSD')
            $cpuS = [double]$ws.CPUScore
            $memS = [double]$ws.MemoryScore
            $dskS = [double]$ws.DiskScore
            $gfxS = [double]$ws.GraphicsScore
            $d3dS = [double]$ws.D3DScore
            Add-Row $g 'Diem CPU' ("{0:N1} / 9.9" -f $cpuS) (Get-ScoreStatus $cpuS 6 4) 'So voi may cung dong chip: thap bat thuong thuong do tan nhiet kem hoac bi gioi han cong suat'
            Add-Row $g 'Diem RAM' ("{0:N1} / 9.9" -f $memS) (Get-ScoreStatus $memS 6 4) 'Thap co the do RAM chay don kenh hoac toc do thap'
            if ($hasSsd) {
                Add-Row $g 'Diem o cung' ("{0:N1} / 9.9" -f $dskS) (Get-ScoreStatus $dskS 7 5.5) 'SSD khoe thuong tren 7; thap hon la o cham hoac xuong cap'
            } else {
                Add-Row $g 'Diem o cung' ("{0:N1} / 9.9" -f $dskS) (Get-ScoreStatus $dskS 5 4) 'O HDD thuong ~5-6; duoi 4 la rat cham'
            }
            Add-Row $g 'Diem do hoa (giao dien)' ("{0:N1} / 9.9" -f $gfxS) $(if ($gfxS -lt 3) { 'WARN' } else { 'INFO' }) 'Card onboard diem trung binh la binh thuong'
            Add-Row $g 'Diem do hoa (3D / game)' ("{0:N1} / 9.9" -f $d3dS) 'INFO' 'Chi co y nghia khi so voi may cung card'
            Add-Row $g 'Luu y khi doc diem' 'Diem chi co y nghia khi so voi may cung dong chip' 'INFO' 'Chay khi cam sac, che do hieu nang cao. Tra diem WinSAT / Cinebench cua cung chip tren mang de doi chieu'
        } else {
            Add-Row $g 'Benchmark' 'Khong lay duoc ket qua WinSAT' 'INFO' 'WinSAT co the khong chay duoc tren may nay (vd mot so ban Windows 11); thu Cinebench hoac CrystalDiskMark'
        }
    }
} else {
    Add-Row $g 'Benchmark' 'Bo qua' 'INFO' 'Chay lai script va chon Y de cham diem CPU/RAM/o cung'
}

# ---------------- STRESS TEST CPU ----------------
$g = 'Stress test CPU'
$ans = $doCpu
if ($ans -match '^[Yy]') {
    $durationSec = 180
    $coreCount = [int]$env:NUMBER_OF_PROCESSORS
    Add-Row $g 'So luong chay' "$coreCount tien trinh, $durationSec giay"

    # Ghi nhan xung nhip truoc test (may dang idle)
    Start-Sleep -Seconds 2
    $idleClock = (Get-CimInstance Win32_Processor | Measure-Object CurrentClockSpeed -Average).Average
    $maxClock  = (Get-CimInstance Win32_Processor | Measure-Object MaxClockSpeed -Average).Average
    Add-Row $g 'Xung khi khong tai' "$([math]::Round($idleClock)) MHz (toi da $([math]::Round($maxClock)) MHz)"

    # Tao tai nang tren tat ca nhan
    $jobs = 1..$coreCount | ForEach-Object {
        Start-Job -ScriptBlock {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $using:durationSec) {
                $x = 0.0001
                1..200000 | ForEach-Object { $x = [math]::Sqrt($x) * 1.0000001 }
            }
        }
    }

    Write-Host "Dang chay tai nang CPU trong $durationSec giay, vui long doi..." -ForegroundColor Yellow
    $samples = New-Object System.Collections.ArrayList
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $durationSec) {
        Start-Sleep -Seconds 5
        $clk = (Get-CimInstance Win32_Processor | Measure-Object CurrentClockSpeed -Average).Average
        $load = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
        [void]$samples.Add([pscustomobject]@{ T = [math]::Round($sw.Elapsed.TotalSeconds); Clock = [math]::Round($clk); Load = [math]::Round($load) })
        Write-Host ("  {0,3}s  xung: {1,5} MHz  tai: {2,3}%" -f [math]::Round($sw.Elapsed.TotalSeconds), [math]::Round($clk), [math]::Round($load))
    }
    Wait-Job -Job $jobs | Out-Null
    $jobs | Remove-Job -Force

    $minClock = ($samples | Measure-Object Clock -Minimum).Minimum
    $avgClockLoad = ($samples | Where-Object Load -gt 80 | Measure-Object Clock -Average).Average
    if (-not $avgClockLoad) { $avgClockLoad = ($samples | Measure-Object Clock -Average).Average }
    $avgLoad = ($samples | Measure-Object Load -Average).Average

    Add-Row $g 'Tai CPU trung binh khi test' "$([math]::Round($avgLoad)) %" $(if ($avgLoad -lt 70) { 'WARN' } else { 'OK' }) 'Neu qua thap, tai chua du nang de phan anh dung'
    Add-Row $g 'Xung thap nhat ghi nhan' "$([math]::Round($minClock)) MHz"
    Add-Row $g 'Xung trung binh khi tai nang' "$([math]::Round($avgClockLoad)) MHz"

    if ($maxClock -gt 0) {
        $pct = $avgClockLoad / $maxClock * 100
        $st = if ($pct -lt 60) { 'BAD' } elseif ($pct -lt 80) { 'WARN' } else { 'OK' }
        Add-Row $g 'So voi xung toi da' "$([math]::Round($pct)) %" $st 'Duoi 80% khi tai nang lien tuc la dau hieu giam xung do nong (throttling) hoac gioi han dien'
    }

    # Kiem tra Event Log xem co loi/tat may bat thuong trong luc test khong
    $testStart = (Get-Date).AddSeconds(-$durationSec - 10)
    $kpDuring = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $testStart }).Count
    Add-Row $g 'Tat may dot ngot trong luc test' $kpDuring $(if ($kpDuring -eq 0) { 'OK' } else { 'BAD' })

    # Luu y ve nhiet do: Windows khong co API nhiet do CPU chuan cho moi may
    $thermal = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature
    if ($thermal) {
        foreach ($t in $thermal) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            if ($celsius -gt 0 -and $celsius -lt 120) {
                $st = if ($celsius -ge 90) { 'BAD' } elseif ($celsius -ge 80) { 'WARN' } else { 'OK' }
                Add-Row $g 'Nhiet do ACPI thermal zone' "$celsius C" $st
            }
        }
    } else {
        Add-Row $g 'Nhiet do CPU' 'Khong doc duoc' 'INFO' 'Windows khong co san API nhiet do dang tin cay tren nhieu laptop; neu can chinh xac hay dung HWiNFO hoac xem BIOS sau khi test'
    }
} else {
    Add-Row $g 'Stress test CPU' 'Bo qua' 'INFO' 'Chay lai script va chon Y neu muon kiem tra'
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
        Add-Row $g 'Pin' 'Khong phat hien pin' 'WARN' 'May ban hoac pin tao/khong nhan'
    }
    foreach ($b in $batts) {
        $design = [double]$b.SelectSingleNode("*[local-name()='DesignCapacity']").InnerText
        $full   = [double]$b.SelectSingleNode("*[local-name()='FullChargeCapacity']").InnerText
        $cyc    = $b.SelectSingleNode("*[local-name()='CycleCount']").InnerText
        if ($design -gt 0) {
            $pct = [math]::Round($full / $design * 100)
            $st = if ($pct -ge 80) { 'OK' } elseif ($pct -ge 60) { 'WARN' } else { 'BAD' }
            Add-Row $g 'Dung luong thiet ke' "$design mWh"
            Add-Row $g 'Dung luong day hien tai' "$full mWh"
            Add-Row $g 'Do chai (con lai)' "$pct %" $st 'Duoi 60% nen tinh them tien thay pin'
        }
        if ($cyc) { Add-Row $g 'So chu ky sac' $cyc $(if ([int]$cyc -gt 800) { 'WARN' } else { 'OK' }) }
    }
} else {
    Add-Row $g 'Bao cao pin' 'Khong tao duoc' 'INFO' 'May co the la desktop hoac khong co pin'
}

# ---------------- NHAT KY LOI PHAN CUNG (90 ngay) ----------------
$g = 'Nhat ky loi (90 ngay gan day)'
$since = (Get-Date).AddDays(-90)

function Enc($t) { return [System.Net.WebUtility]::HtmlEncode([string]$t) }
function Short-Text($t, $max = 220) {
    $line = ([string]$t -split "`r?`n")[0].Trim()
    if ($line.Length -gt $max) { $line = $line.Substring(0, $max) + '...' }
    return $line
}
function Fmt-Time($d) { return ([datetime]$d).ToString('dd/MM/yyyy HH:mm') }

# ---- WHEA / Kernel-Power / Display: dem + thoi diem + noi dung cu the ----
$wheaEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since })
$kpEv   = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since })
$dispEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $since })

$note = ''
if ($wheaEv.Count -gt 0) {
    $lastW = $wheaEv | Sort-Object TimeCreated | Select-Object -Last 1
    $note = "Gan nhat: $(Fmt-Time $lastW.TimeCreated). Noi dung goc: $(Enc (Short-Text $lastW.Message))"
}
Add-Row $g 'Loi phan cung WHEA (CPU/RAM/bus)' $wheaEv.Count $(if ($wheaEv.Count -eq 0) { 'OK' } elseif ($wheaEv.Count -lt 5) { 'WARN' } else { 'BAD' }) $note

$note = 'Nhieu thuong do qua nhiet hoac loi nguon/pin'
if ($kpEv.Count -gt 0) {
    $lastK = $kpEv | Sort-Object TimeCreated | Select-Object -Last 1
    $bug = $null
    try { $bug = $lastK.Properties[0].Value } catch { }
    $bugText = ''
    if ($null -ne $bug) {
        if ([int64]$bug -eq 0) { $bugText = ' Ma BugcheckCode = 0: may mat dien dot ngot hoac bi giu nut nguon, khong phai man hinh xanh.' }
        else { $bugText = " Ma BugcheckCode = 0x{0:X}: tat do loi he thong (man hinh xanh)." -f [int64]$bug }
    }
    $note = "Gan nhat: $(Fmt-Time $lastK.TimeCreated).$bugText Nhieu lan thuong do qua nhiet, loi nguon/pin hoac pin yeu."
}
Add-Row $g 'Tat may dot ngot (Kernel-Power 41)' $kpEv.Count $(if ($kpEv.Count -eq 0) { 'OK' } elseif ($kpEv.Count -lt 5) { 'WARN' } else { 'BAD' }) $note

$note = 'Driver card do hoa bi treo roi tu hoi phuc'
if ($dispEv.Count -gt 0) {
    $lastD = $dispEv | Sort-Object TimeCreated | Select-Object -Last 1
    $note = "Gan nhat: $(Fmt-Time $lastD.TimeCreated). Driver card do hoa bi treo roi tu hoi phuc; nhieu lan la dau hieu loi driver hoac card."
}
Add-Row $g 'Driver man hinh bi treo (Display 4101)' $dispEv.Count $(if ($dispEv.Count -eq 0) { 'OK' } elseif ($dispEv.Count -lt 5) { 'WARN' } else { 'BAD' }) $note

# ---- Loi o dia / luu tru: phan loai theo tung o va giai thich cu the ----
# Moi muc: Ten loi | Muc do | Y nghia | Cach xu ly
$evCatalog = @{
    'disk:7'       = @('Bad block (khoi hong tren o)', 'BAD', 'O phat hien khoi (block) hong khi doc hoac ghi.', 'Sao luu du lieu ngay, kiem tra SMART va quet be mat. Neu la o trong may thi nghi o hong.')
    'disk:9'       = @('O khong phan hoi trong thoi gian cho (timeout)', 'WARN', 'Thao tac doc/ghi bi het thoi gian cho.', 'Thuong do cap/cong USB chap chon hoac o dang bi loi. Voi o trong may can theo doi va kiem tra SMART.')
    'disk:11'      = @('Loi bo dieu khien o (controller error)', 'WARN', 'Bo dieu khien, cap hoac cong ket noi bao loi.', 'Kiem tra cap va cong. Voi o trong may, nghi mach dieu khien hoac o.')
    'disk:15'      = @('O chua san sang truy cap', 'WARN', 'O tam thoi khong san sang (mat ket noi, ngu sau, dang khoi dong lai).', 'Voi o USB thuong do tiet kiem dien; voi o trong may nen theo doi them.')
    'disk:51'      = @('Loi khi doc/ghi bo nho ao (paging error)', 'WARN', 'Windows gap loi khi doc/ghi du lieu bo nho tren o. Hay xay ra khi o bi mat ket noi luc dang chay chuong trinh tu o do, hoac cap/cong chap chon, hoac o loi.', 'Voi o USB: rut dung cach (Eject), doi cap/cong. Voi o trong may: kiem tra SMART va quet be mat ngay.')
    'disk:52'      = @('O du doan sap hong (SMART)', 'BAD', 'O tu bao hieu sap hong theo SMART.', 'Sao luu du lieu ngay va thay o.')
    'disk:153'     = @('Thao tac doc/ghi phai thu lai', 'WARN', 'Doc/ghi khong thanh cong lan dau, phai thu lai.', 'Thuong do cap/cong chap chon hoac o cham; nhieu lan tren o trong may la dau hieu xuong cap.')
    'disk:154'     = @('Thao tac doc/ghi that bai do loi phan cung', 'BAD', 'O bao loi phan cung khi doc/ghi.', 'Sao luu du lieu, kiem tra SMART; voi o trong may nen thay.')
    'disk:157'     = @('O bi rut dot ngot (khong bam Eject)', 'INFO', 'O bi go ra khi chua duoc ngat an toan.', 'Khong phai loi o, chi la rut USB/o ngoai dot ngot.')
    'Ntfs:55'      = @('He thong tep bi hong cau truc', 'BAD', 'Windows phat hien hong cau truc he thong tep tren mot phan vung.', 'Sao luu truoc, roi chay chkdsk /f cho phan vung do (them /r de quet be mat).')
    'stornvme:129' = @('Bo dieu khien NVMe bi reset', 'WARN', 'Bo dieu khien phai reset vi o khong phan hoi kip.', 'Nhieu lan tren o trong may la dau hieu o hoac firmware co van de; cap nhat firmware va kiem tra SMART.')
    'storahci:129' = @('Bo dieu khien SATA/AHCI bi reset', 'WARN', 'Bo dieu khien phai reset vi o khong phan hoi kip.', 'Nhieu lan tren o trong may la dau hieu cap, o hoac nguon co van de; kiem tra SMART.')
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
    $label = 'Bo dieu khien / phan vung (xem noi dung goc)'
    if ($prov -eq 'disk') {
        $num = $null
        if ($msg -match 'Harddisk(\d+)') { $num = [int]$Matches[1] }
        if ($null -ne $num -and $diskMap.ContainsKey($num)) {
            $dk = $diskMap[$num]
            $label = "Harddisk$num ($($dk.BusType): $($dk.FriendlyName))"
            if ($dk.BusType -eq 'USB') { $kind = 'usb' }
        } elseif ($null -ne $num) {
            $label = "Harddisk$num (hien khong con ket noi)"
            $kind = 'gone'
        } else {
            $label = 'Khong xac dinh duoc o'
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

# Tong hop cho o gan trong may (bo qua o USB va su kien rut o)
$intBad = 0; $intWarn = 0; $intEvents = 0
foreach ($o in $groups.Values) {
    if ($o.Kind -ne 'internal') { continue }
    $sev = $evCatalog[$o.Key][1]
    $intEvents += $o.Count
    if ($sev -eq 'BAD') { $intBad++ } elseif ($sev -eq 'WARN') { $intWarn++ }
}
$sumSt = if ($intBad -gt 0) { 'BAD' } elseif ($intWarn -gt 0) { 'WARN' } else { 'OK' }
$sumNote = 'Tong hop su kien loi o dia/luu tru tren o gan trong may (bo qua o USB va su kien rut o). Chi tiet tung loi o ben duoi.'
if ($intEvents -eq 0) { $sumNote = 'Khong co su kien loi o dia nghiem trong tren o trong may trong 90 ngay.' }
Add-Row $g 'Loi o dia / luu tru - o trong may' "$intEvents su kien" $sumSt $sumNote

# Chi tiet tung loi: ten loi, o nao, bao nhieu lan, bao nhieu dot, khi nao, noi dung goc
foreach ($gk in ($groups.Keys | Sort-Object)) {
    $o = $groups[$gk]
    $cat = $evCatalog[$o.Key]
    $times = @($o.Times | Sort-Object)
    $bursts = 1
    for ($i = 1; $i -lt $times.Count; $i++) {
        if (($times[$i] - $times[$i - 1]).TotalSeconds -gt 120) { $bursts++ }
    }
    $value = "{0} su kien trong {1} dot (lan dau {2}, gan nhat {3})" -f $o.Count, $bursts, (Fmt-Time $times[0]), (Fmt-Time $times[$times.Count - 1])
    $st = 'INFO'
    $kindNote = ''
    switch ($o.Kind) {
        'internal' { $st = $cat[1] }
        'usb'      { $st = 'INFO'; $kindNote = ' Day la o USB/ngoai nen khong anh huong ket luan ve may.' }
        'gone'     { $st = 'INFO'; $kindNote = ' O nay hien khong con ket noi (thuong la USB da rut).' }
        'unknown'  { $st = 'WARN'; $kindNote = ' Khong xac dinh duoc o nao.' }
    }
    $detailNote = "Y nghia: $($cat[2]) Cach xu ly: $($cat[3])$kindNote Noi dung goc: $(Enc $o.Sample)"
    Add-Row $g "$($cat[0]) - $($o.Label) [$($o.Key)]" $value $st $detailNote
}
Add-Row $g 'Xem them chi tiet' 'Get-WinEvent -FilterHashtable @{LogName=''System''; ProviderName=''disk''} | Select TimeCreated, Id, Message | Format-List' 'INFO' 'Chay trong PowerShell (Admin) de xem tung su kien. So thu tu o (Harddisk N) co the doi theo thoi diem cam/rut.'
Add-Row $g 'Luu y' 'May moi cai lai Windows thi nhat ky bi xoa nen it thong tin' 'INFO'

# ---------------- KET LUAN ----------------
$bad  = @($rows | Where-Object Status -eq 'BAD').Count
$warn = @($rows | Where-Object Status -eq 'WARN').Count
if     ($bad -ge 1)  { $verdict = "KHONG NEN MUA (hoac chi mua gia rat re): co $bad muc XAU, $warn muc canh bao"; $vcol = '#c0392b' }
elseif ($warn -ge 3) { $verdict = "CAN NHAC / THUONG LUONG GIA: co $warn muc canh bao"; $vcol = '#d68910' }
elseif ($warn -ge 1) { $verdict = "TAM ON: co $warn muc canh bao nho, kiem tra them bang mat"; $vcol = '#7d8c00' }
else                 { $verdict = "TOT theo so lieu doc duoc (van phai kiem tra man hinh, ban phim, cong ket noi bang mat)"; $vcol = '#1e8449' }

# ---------------- XUAT BAO CAO ----------------
$colors = @{ OK = '#d5f5e3'; WARN = '#fcf3cf'; BAD = '#f5b7b1'; INFO = '#ffffff' }
$label  = @{ OK = 'OK'; WARN = 'CANH BAO'; BAD = 'XAU'; INFO = '' }
$html = New-Object System.Text.StringBuilder
[void]$html.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Bao cao laptop</title>')
[void]$html.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;max-width:960px}table{border-collapse:collapse;width:100%;margin-bottom:18px}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left;font-size:14px}th{background:#eee}h3{margin:18px 0 6px}.v{padding:14px;color:#fff;font-size:18px;font-weight:bold;border-radius:6px}</style></head><body>')
[void]$html.AppendLine("<h2>Bao cao kiem tra laptop - $(Get-Date -Format 'dd/MM/yyyy HH:mm')</h2>")
[void]$html.AppendLine("<div class='v' style='background:$vcol'>$verdict</div>")
foreach ($grp in ($rows | Group-Object Group)) {
    [void]$html.AppendLine("<h3>$($grp.Name)</h3><table><tr><th style='width:30%'>Muc</th><th style='width:32%'>Gia tri</th><th style='width:10%'>Danh gia</th><th>Ghi chu</th></tr>")
    foreach ($r in $grp.Group) {
        [void]$html.AppendLine("<tr style='background:$($colors[$r.Status])'><td>$($r.Item)</td><td>$($r.Value)</td><td>$($label[$r.Status])</td><td>$($r.Note)</td></tr>")
    }
    [void]$html.AppendLine('</table>')
}
[void]$html.AppendLine('<p><b>Chua kiem tra duoc bang phan mem:</b> man hinh (diem chet), ban phim, touchpad, cong USB/HDMI, loa, mic, webcam, Wi-Fi, ban le, vo may, tinh trang khoa BIOS/MDM, kich hoat Windows. Cac chi so tren do firmware tu khai nen co the bi chinh sua; hay ket hop test thuc te.</p></body></html>')

$serial = ($bios.SerialNumber -replace '[^\w-]', '')
$out = Join-Path $PSScriptRoot "BaoCao_$serial.html"
$html.ToString() | Set-Content -Path $out -Encoding UTF8

# ---------------- IN RA MAN HINH ----------------
Write-Host ""
foreach ($grp in ($rows | Group-Object Group)) {
    Write-Host "== $($grp.Name)" -ForegroundColor Cyan
    foreach ($r in $grp.Group) {
        $col = switch ($r.Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'BAD' { 'Red' } default { 'Gray' } }
        Write-Host ("  [{0,-8}] {1}: {2}" -f $label[$r.Status], $r.Item, $r.Value) -ForegroundColor $col
    }
}
Write-Host ""
Write-Host "KET LUAN: $verdict" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "Da luu bao cao: $out" -ForegroundColor Cyan
Start-Process $out
$md = Read-Host "Mo Windows Memory Diagnostic de test TOAN BO RAM? (can khoi dong lai may, mat 10-30 phut; bao cao da luu o tren) (Y/N)"
if ($md -match '^[Yy]') { Start-Process mdsched.exe }
[void](Read-Host "Nhan Enter de thoat")
