<#
.SYNOPSIS
    Сборка OpenWrt 25.12 для Khadas Edge-V и x86 (ПК, виртуальные машины, 32 бит) на Windows 11.

.DESCRIPTION
    Скрипт всё делает сам, всё хранится на диске D: (папка -Root):
      1. включает WSL2 (если его нет: права администратора + перезагрузка,
         после перезагрузки скрипт продолжит сам);
      2. скачивает официальный образ Ubuntu 24.04 для WSL, проверяет SHA256
         и разворачивает его в D:\KhadasEdgeBuild\wsl;
      3. ставит в Ubuntu всё нужное для сборки OpenWrt;
      4. скачивает исходники и собирает прошивку (первая сборка 1-4 часа,
         повторные - быстрее);
      5. кладёт готовые образы в D:\KhadasEdgeBuild\out.

    Повторный запуск обновляет исходники и дособирает изменения.

.PARAMETER Root
    Рабочая папка (диск с NTFS, нужно ~60 ГБ свободного места). По умолчанию D:\KhadasEdgeBuild

.PARAMETER Branch
    Ветка репозитория с проектом.

.PARAMETER Targets
    Что собирать, через запятую (по умолчанию edge-v):
      edge-v       Khadas Edge-V (сборка из исходников, 1-4 часа)
      x86-64-pc    ПК / сервер x86_64 (официальный ImageBuilder, минуты)
      x86-64-vm    виртуальная машина: Proxmox qcow2, VMware vmdk, VirtualBox vdi, Hyper-V vhdx
      i386-pc      32-битный ПК (Pentium 4 и новее)
      i386-legacy  очень старый ПК (i486 / Pentium / Pentium III)
      all          всё перечисленное

.PARAMETER Jobs
    Число параллельных потоков сборки, 0 = автоматически по CPU и памяти.

.PARAMETER ZtController
    Собрать со своим контроллером ZeroTier (лицензия ZeroTier: только
    некоммерческое использование, такие образы нельзя распространять).

.PARAMETER Clean
    Очистить результаты прошлой сборки (make clean) перед сборкой.

.PARAMETER NoBuild
    Только подготовить окружение и исходники, без сборки.

.PARAMETER Uninstall
    Удалить Ubuntu для сборки (WSL-дистрибутив) и рабочую папку.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build-khadas-edge.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build-khadas-edge.ps1 -Root E:\khadas -Jobs 8

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build-khadas-edge.ps1 -Targets x86-64-vm,x86-64-pc
#>

[CmdletBinding()]
param(
    [string]$Root = 'D:\KhadasEdgeBuild',
    [string]$Distro = 'khadas-build',
    [string]$Repo = 'https://github.com/220242/khadas_edge-openwrt.git',
    [string]$Branch = 'nokvm',
    [string]$Targets = 'edge-v',
    [int]$Jobs = 0,
    [switch]$ZtController,
    [switch]$Clean,
    [switch]$NoBuild,
    [switch]$Uninstall
)

# native tools (wsl.exe, curl.exe) are checked by exit code; 'Stop' would turn
# their stderr output into exceptions in Windows PowerShell 5.1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$env:WSL_UTF8 = '1'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$ScriptArgs = $PSBoundParameters
$UbuntuBase = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/current'
$UbuntuFile = 'ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz'
$BuildUser = 'builder'
$MinFreeGB = 60

# ---------------------------------------------------------------- helpers

function Say([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Die([string]$Message) {
    Write-Host "[x] $Message" -ForegroundColor Red
    Set-KeepAwake $false
    exit 1
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# do not let Windows sleep during the build (WSL would pause)
function Set-KeepAwake([bool]$On) {
    try {
        if (-not ('KhadasBuild.Power' -as [type])) {
            Add-Type -Namespace KhadasBuild -Name Power -MemberDefinition `
                '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
        }
        if ($On) {
            [void][KhadasBuild.Power]::SetThreadExecutionState([uint32]'0x80000001')   # CONTINUOUS | SYSTEM_REQUIRED
        } else {
            [void][KhadasBuild.Power]::SetThreadExecutionState([uint32]'0x80000000')   # CONTINUOUS
        }
    } catch { }
}

# D:\Foo Bar -> /mnt/d/Foo Bar
function ConvertTo-WslPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\') { Die "Нужен путь на локальном диске: $Path" }
    $drive = $full.Substring(0, 1).ToLower()
    $rest = $full.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

# text file for Linux: UTF-8 without BOM, LF line ends
function Write-LinuxFile([string]$Path, [string]$Text) {
    $Text = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-WslDistros {
    $out = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return @() }
    return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

function Test-WslReady {
    & wsl.exe --version *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-VmPlatform {
    try {
        $f = Get-CimInstance -ClassName Win32_OptionalFeature -Filter "Name='VirtualMachinePlatform'"
        # unknown state: do not force a reboot loop
        if ($null -eq $f) { return $true }
        return ($f.InstallState -eq 1)
    } catch {
        return $true
    }
}

# run this script again after the reboot
function Register-Resume {
    $parts = @('powershell.exe', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($k in $ScriptArgs.Keys) {
        $v = $ScriptArgs[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) {
            if ($v.IsPresent) { $parts += "-$k" }
        } else {
            $parts += "-$k"
            $parts += "`"$v`""
        }
    }
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' `
        -Name 'KhadasEdgeBuild' -Value ($parts -join ' ') -PropertyType String -Force | Out-Null
}

function Invoke-InDistro([string]$User, [string[]]$Command) {
    # Out-Host: show the output, return only the exit code
    & wsl.exe -d $Distro -u $User -- @Command | Out-Host
    return $LASTEXITCODE
}

# ---------------------------------------------------------------- uninstall

if ($Uninstall) {
    if ((Get-WslDistros) -contains $Distro) {
        Say "Удаление WSL-дистрибутива $Distro"
        & wsl.exe --unregister $Distro
    }
    if (Test-Path $Root) {
        $answer = Read-Host "Удалить папку $Root со скачанными файлами и готовыми образами? (y/n)"
        if ($answer -match '^[yYдД]') { Remove-Item -Recurse -Force $Root }
    }
    Say 'Готово'
    exit 0
}

# ---------------------------------------------------------------- checks

Write-Host ''
Write-Host '  Сборка OpenWrt 25.12 для Khadas Edge (RK3399)' -ForegroundColor Green
Write-Host "  Рабочая папка: $Root, ветка: $Branch" -ForegroundColor Green
Write-Host ''

if (-not [Environment]::Is64BitOperatingSystem) { Die 'Нужна 64-битная Windows' }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 19041) { Die "Для WSL2 нужна Windows 10 2004+ / Windows 11 (сборка $build)" }

$qualifier = Split-Path -Qualifier ([IO.Path]::GetFullPath($Root))
$letter = $qualifier.Substring(0, 1)
$drive = New-Object System.IO.DriveInfo($letter)
if (-not $drive.IsReady) { Die "Диск $qualifier не найден" }
if ($drive.DriveFormat -notin @('NTFS', 'ReFS')) { Die "Диск $qualifier должен быть NTFS (сейчас $($drive.DriveFormat))" }
$freeGB = [math]::Floor($drive.AvailableFreeSpace / 1GB)
if ($freeGB -lt $MinFreeGB) {
    Warn "На диске $qualifier свободно $freeGB ГБ, для сборки нужно около $MinFreeGB ГБ"
}

$ramGB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$cpus = [Environment]::ProcessorCount
if ($Jobs -le 0) {
    # WSL gets half of the RAM, ~1.5 GB per compiler job
    $Jobs = [int][math]::Max(1, [math]::Min($cpus, [math]::Floor(($ramGB / 2) / 1.5)))
}
Say "CPU: $cpus, RAM: $ramGB ГБ, потоков сборки: $Jobs, свободно на $qualifier`: $freeGB ГБ"
if ($ramGB -lt 8) { Warn 'Меньше 8 ГБ RAM: сборка может упасть из-за нехватки памяти, попробуйте -Jobs 1' }

foreach ($d in @($Root, "$Root\downloads", "$Root\wsl", "$Root\scripts", "$Root\out", "$Root\logs")) {
    New-Item -ItemType Directory -Force -Path $d -ErrorAction Stop | Out-Null
}

# ---------------------------------------------------------------- WSL2

$needReboot = -not (Test-VmPlatform)
if (-not (Test-WslReady) -or $needReboot) {
    Say 'Установка WSL2 (подтвердите запрос прав администратора)'
    if (Test-Admin) {
        & wsl.exe --install --no-distribution
        $code = $LASTEXITCODE
    } else {
        try {
            $p = Start-Process -FilePath 'wsl.exe' -ArgumentList '--install', '--no-distribution' `
                -Verb RunAs -Wait -PassThru -ErrorAction Stop
            $code = $p.ExitCode
        } catch {
            Die 'Нужны права администратора для установки WSL'
        }
    }
    if ($code -ne 0) { Die "Установка WSL завершилась с кодом $code" }

    if ($needReboot -or -not (Test-WslReady)) {
        Register-Resume
        Warn 'Для WSL2 нужна перезагрузка. После перезагрузки скрипт продолжит работу сам.'
        $answer = Read-Host 'Перезагрузить сейчас? (y/n)'
        if ($answer -match '^[yYдД]') { Restart-Computer -Force }
        exit 0
    }
}
& wsl.exe --set-default-version 2 *> $null

# ---------------------------------------------------------------- Ubuntu

if ((Get-WslDistros) -notcontains $Distro) {
    $tar = Join-Path "$Root\downloads" $UbuntuFile

    Say 'Проверка контрольной суммы образа Ubuntu 24.04'
    $sums = & curl.exe -sSL --fail --retry 3 "$UbuntuBase/SHA256SUMS"
    if ($LASTEXITCODE -ne 0) { Die 'Не удалось скачать SHA256SUMS (нет интернета?)' }
    $line = @($sums | Where-Object { $_ -match [regex]::Escape($UbuntuFile) + '$' })[0]
    if (-not $line) { Die "В SHA256SUMS нет $UbuntuFile" }
    $expected = ($line -split '\s+')[0].ToLower()

    $ok = (Test-Path $tar) -and ((Get-FileHash -Algorithm SHA256 $tar).Hash.ToLower() -eq $expected)
    if (-not $ok) {
        Say 'Скачивание Ubuntu 24.04 для WSL (~350 МБ)'
        & curl.exe -L --fail --retry 5 -C - -o $tar "$UbuntuBase/$UbuntuFile"
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -Force $tar -ErrorAction SilentlyContinue
            & curl.exe -L --fail --retry 5 -o $tar "$UbuntuBase/$UbuntuFile"
            if ($LASTEXITCODE -ne 0) { Die 'Не удалось скачать образ Ubuntu' }
        }
        if ((Get-FileHash -Algorithm SHA256 $tar).Hash.ToLower() -ne $expected) {
            Remove-Item -Force $tar
            Die 'Контрольная сумма образа Ubuntu не совпадает, запустите скрипт ещё раз'
        }
    }

    Say "Развёртывание Ubuntu в $Root\wsl"
    & wsl.exe --import $Distro "$Root\wsl" $tar --version 2
    if ($LASTEXITCODE -ne 0) {
        Warn 'Если ошибка про виртуализацию: включите VT-x / AMD-V (SVM) в BIOS и перезагрузитесь.'
        Die 'wsl --import не удался'
    }
}

# ---------------------------------------------------------------- packages

$setupSh = @'
#!/bin/bash
# khadas-build: user + packages for the OpenWrt build (runs as root)
set -e
export DEBIAN_FRONTEND=noninteractive
BUILD_USER="$1"

id "$BUILD_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$BUILD_USER"
B_UID=$(id -u "$BUILD_USER")
B_GID=$(id -g "$BUILD_USER")

# no Windows PATH (spaces break the OpenWrt build), build user by default,
# Windows drives (/mnt/d) owned by the build user so it can write out/ and logs/
cat > /etc/wsl.conf <<EOF
[boot]
systemd=false

[user]
default=$BUILD_USER

[automount]
options = "uid=$B_UID,gid=$B_GID,umask=022"

[interop]
appendWindowsPath=false
EOF

MARK=/var/lib/khadas-build-deps-v2
if [ ! -f "$MARK" ]; then
	apt-get update
	apt-get install -y --no-install-recommends \
		build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
		gettext git libncurses-dev libssl-dev python3 python3-dev \
		python3-setuptools python3-pyelftools rsync swig unzip zlib1g-dev \
		file wget curl ca-certificates bzip2 zstd xz-utils patch perl qemu-utils \
		diffutils time tar sudo
	touch "$MARK"
fi

mkdir -p /etc/sudoers.d
echo "$BUILD_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$BUILD_USER"
chmod 440 "/etc/sudoers.d/$BUILD_USER"
echo "khadas-build: packages ready"
'@

$buildSh = @'
#!/bin/bash
# khadas-build: fetch the project and build OpenWrt (runs as the build user)
set -eo pipefail
REPO="$1"; BRANCH="$2"; JOBS="$3"; ZT="$4"; CLEAN="$5"; MODE="$6"; OUT="$7"; LOG="$8"
TARGETS="${9:-edge-v}"
[ "$TARGETS" = all ] && TARGETS=edge-v,x86-64-pc,x86-64-vm,i386-pc,i386-legacy
EDGE=0
X86=
for t in ${TARGETS//,/ }; do
	case "$t" in
		edge-v) EDGE=1 ;;
		x86-64-pc|x86-64-vm|i386-pc|i386-legacy) X86="$X86 $t" ;;
		*) echo "ОШИБКА: неизвестная цель $t" >&2; exit 2 ;;
	esac
done

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C.UTF-8
umask 022

mkdir -p "$OUT" "$(dirname "$LOG")" 2>/dev/null || true
if ! touch "$LOG" 2>/dev/null || ! touch "$OUT/.write-test" 2>/dev/null; then
	echo "ОШИБКА: нет прав на запись в $OUT или $LOG." >&2
	echo "Выполните в PowerShell: wsl --shutdown  и запустите скрипт ещё раз." >&2
	exit 3
fi
rm -f "$OUT/.write-test"

PROJECT="$HOME/khadas_edge-openwrt"
if [ -d "$PROJECT/.git" ]; then
	echo "==> обновление проекта ($BRANCH)"
	git -C "$PROJECT" fetch --depth 50 origin "$BRANCH"
	git -C "$PROJECT" checkout -q -B "$BRANCH" FETCH_HEAD
else
	echo "==> скачивание проекта ($BRANCH)"
	git clone --depth 50 --branch "$BRANCH" "$REPO" "$PROJECT"
fi
cd "$PROJECT"
echo "==> проект: $(git log -1 --format='%h %s')"

if [ "$CLEAN" = 1 ] && [ -d build/openwrt ]; then
	echo "==> make clean"
	make -C build/openwrt clean
fi

STEP=
[ "$MODE" = prepare ] && STEP=prepare
{
	if [ "$EDGE" = 1 ]; then
		echo "==> Khadas Edge-V"
		JOBS="$JOBS" ZT_CONTROLLER="$ZT" OUT="$OUT" ./openwrt/build.sh $STEP
	fi
	if [ -n "$X86" ] && [ "$MODE" != prepare ]; then
		echo "==> пакеты для x86 (официальный SDK)"
		FEED_OUT="$OUT/feed" ./openwrt/ib/sdk-feed.sh
		for v in $X86; do
			echo "==> $v (официальный ImageBuilder)"
			FEED_OUT="$OUT/feed" OUT="$OUT" ./openwrt/ib/imagebuilder.sh "$v"
		done
	fi
} 2>&1 | tee "$LOG"
'@

Write-LinuxFile "$Root\scripts\setup-root.sh" $setupSh
Write-LinuxFile "$Root\scripts\build.sh" $buildSh
$wslRoot = ConvertTo-WslPath $Root

Say 'Установка пакетов для сборки в Ubuntu (первый раз несколько минут)'
$code = Invoke-InDistro 'root' @('bash', "$wslRoot/scripts/setup-root.sh", $BuildUser)
if ($code -ne 0) { Die "Установка пакетов не удалась (код $code)" }
# apply /etc/wsl.conf
& wsl.exe --terminate $Distro *> $null

# ---------------------------------------------------------------- build

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logWin = "$Root\logs\build-$stamp.log"
$zt = '0'
if ($ZtController) {
    $zt = '1'
    Warn 'Контроллер ZeroTier: только некоммерческое использование, образ нельзя распространять'
}
$cleanArg = '0'
if ($Clean) { $cleanArg = '1' }
$mode = 'build'
if ($NoBuild) { $mode = 'prepare' }

if ($NoBuild) {
    Say 'Подготовка исходников (без сборки)'
} else {
    Say "Сборка OpenWrt, потоков: $Jobs. Первая сборка занимает 1-4 часа, компьютер не уснёт."
}
Say "Лог: $logWin"

Set-KeepAwake $true
$started = Get-Date
$code = Invoke-InDistro $BuildUser @('bash', "$wslRoot/scripts/build.sh",
    $Repo, $Branch, "$Jobs", $zt, $cleanArg, $mode, "$wslRoot/out", (ConvertTo-WslPath $logWin), $Targets)
Set-KeepAwake $false
$elapsed = (Get-Date) - $started

if ($code -ne 0) {
    Warn "Лог: $logWin"
    Die "Сборка завершилась с ошибкой (код $code). Запустите скрипт ещё раз: сборка продолжится с места остановки."
}

if ($NoBuild) {
    Say ('Готово. Исходники: \\wsl$\' + $Distro + '\home\' + $BuildUser + '\khadas_edge-openwrt\build\openwrt')
    exit 0
}

Write-Host ''
Say ('Сборка завершена за {0:hh\:mm\:ss}. Образы:' -f $elapsed)
Get-ChildItem "$Root\out" -Recurse -Include '*.img.gz', '*.qcow2', '*.vmdk', '*.vdi', '*.vhdx' |
    Where-Object { $_.FullName -notmatch '\\apk-repo\\' } | Sort-Object FullName |
    ForEach-Object { Write-Host ("    {0}  ({1:N0} МБ)" -f $_.FullName, ($_.Length / 1MB)) -ForegroundColor Green }
Write-Host ''
Write-Host '  Запись на SD / eMMC / USB: balenaEtcher или Rufus (файл .img.gz можно записывать без распаковки).'
Write-Host '  Proxmox: qm importdisk <vmid> openwrt-...-x86-64-vm.qcow2 local-lvm (подробнее: selector\index.html).'
Write-Host '  Ethernet - к домашнему роутеру: плата появится в нём как khadas-edge, адрес виден и на HDMI.'
Write-Host '  Веб-интерфейс: http://khadas-edge.local/ или по этому адресу, root / khadasedge (смените пароль).'
Write-Host '  Wi-Fi Khadas-Edge / khadasedge, из Wi-Fi: http://192.168.77.1'
Write-Host ('  Модули ядра этой сборки: ' + $Root + '\out\apk-repo')
Write-Host ''
Start-Process explorer.exe "$Root\out"
