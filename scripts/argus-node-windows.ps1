<#
.SYNOPSIS
  Argus Wi-Fi node for a Windows PC or laptop (issue #1: "two PCs as a cluster").

.DESCRIPTION
  Downloads ggml rpc-server from llama.cpp b12008 (the same build as the Argus desktop app: the RPC
  protocol must match), runs `ggml-rpc-server.exe -H 0.0.0.0 -p 50052` and broadcasts the Argus beacon
  every 2 s to UDP 50053:
    {"argus":"node","v":1,"name":"<PC>","port":50052,"ram_mb":N,"free_mb":N,"variant":"..."}
  The PC then shows up in Argus -> Cluster -> "Найдено в сети" (button "Добавить").

  Build choice (auto): NVIDIA GPU with a recent driver -> CUDA build; Vulkan driver present
  (System32\vulkan-1.dll) -> Vulkan build; otherwise the CPU build. Force one with -Backend.

  !! rpc-server has NO password and NO encryption: closed home network only, never expose port 50052.

.EXAMPLE
  argus-node-windows.cmd                      run in this window (Ctrl+C stops everything)
  argus-node-windows.cmd -Install             autostart at logon (Scheduled Task) and start now
  argus-node-windows.cmd -Uninstall           remove autostart, firewall rule and files
  argus-node-windows.cmd -OpenFirewall        only add the Windows Firewall rule (asks for admin)
  argus-node-windows.cmd -Backend vulkan      force the Vulkan build (cpu | vulkan | cuda | auto)

  Env: ARGUS_PORT=50052 ARGUS_NODE_NAME="Laptop" ARGUS_THREADS=8 ARGUS_BEACON_TARGET=192.168.1.10
       ARGUS_LANG=ru|en ARGUS_YES=1 ARGUS_RPC_BIN=C:\path\ggml-rpc-server.exe (skip download)
#>
[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$OpenFirewall,
  [ValidateSet('auto', 'cpu', 'vulkan', 'cuda')]
  [string]$Backend = 'auto',
  [int]$Port = 0,
  [string]$Name = '',
  [int]$Threads = 0,
  [string]$BeaconTarget = '',
  [switch]$Yes,
  [ValidateSet('', 'ru', 'en')]
  [string]$Lang = '',
  [switch]$Background   # internal: started by the Scheduled Task (hidden window, logs to node.log)
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is 10x slower with the progress bar in PS 5.1
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# ------------------------------------------------------------------ settings
$LlamaRef   = 'b12008'
$Rel        = "https://github.com/ggml-org/llama.cpp/releases/download/$LlamaRef"
$BeaconPort = 50053
$Dir        = Join-Path $env:LOCALAPPDATA 'ArgusNode'
$TaskName   = 'Argus Node'
$RuleName   = 'Argus Node (rpc-server)'
$RawScript  = 'https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/argus-node-windows.ps1'

if ($Port -le 0)    { if ($env:ARGUS_PORT) { $Port = [int]$env:ARGUS_PORT } else { $Port = 50052 } }
if (-not $Name)     { if ($env:ARGUS_NODE_NAME) { $Name = $env:ARGUS_NODE_NAME } else { $Name = $env:COMPUTERNAME } }
if ($Threads -le 0) { if ($env:ARGUS_THREADS) { $Threads = [int]$env:ARGUS_THREADS } else { $Threads = [Environment]::ProcessorCount } }
if (-not $BeaconTarget -and $env:ARGUS_BEACON_TARGET) { $BeaconTarget = $env:ARGUS_BEACON_TARGET }
if ($env:ARGUS_YES -eq '1') { $Yes = $true }
if (-not $Lang) {
  if ($env:ARGUS_LANG) { $Lang = $env:ARGUS_LANG }
  elseif ((Get-UICulture).Name -like 'ru*' -or (Get-Culture).Name -like 'ru*') { $Lang = 'ru' }
  else { $Lang = 'en' }
}
if ($Lang -ne 'ru') { $Lang = 'en' }

# ------------------------------------------------------------------ text helpers
function T([string]$ru, [string]$en) { if ($Lang -eq 'ru') { return $ru } else { return $en } }
function Say([string]$ru, [string]$en, [string]$color = 'Gray') { Write-Host (T $ru $en) -ForegroundColor $color }
function Info([string]$ru, [string]$en) { Write-Host '==> ' -ForegroundColor Cyan -NoNewline; Write-Host (T $ru $en) }
function Ok([string]$ru, [string]$en)   { Write-Host ' OK ' -ForegroundColor Green -NoNewline; Write-Host (T $ru $en) }
function Warn([string]$ru, [string]$en) { Write-Host ' !! ' -ForegroundColor Yellow -NoNewline; Write-Host (T $ru $en) -ForegroundColor Yellow }
function Fail([string]$ru, [string]$en) { Write-Host ' XX ' -ForegroundColor Red -NoNewline; Write-Host (T $ru $en) -ForegroundColor Red; throw 'argus-node: stopped' }
function Log([string]$text) { Write-Host "[argus-node] $text" }

function Ask([string]$ru, [string]$en, [bool]$default = $false) {
  if ($Yes) { return $true }
  if ($Background) { return $default }
  $hint = '[y/N]'; if ($default) { $hint = '[Y/n]' }
  Write-Host '? ' -ForegroundColor Cyan -NoNewline
  $a = Read-Host ((T $ru $en) + " $hint")
  if ([string]::IsNullOrWhiteSpace($a)) { return $default }
  return ($a -match '^\s*[yYдД]')
}

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Run a PowerShell snippet as administrator (UAC prompt). Returns $true if it exited with 0.
function Invoke-Elevated([string]$code) {
  if (Test-Admin) {
    try { & ([scriptblock]::Create($code)); return $true } catch { Write-Host $_ -ForegroundColor Red; return $false }
  }
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  try {
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
         -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
    return ($p.ExitCode -eq 0)
  } catch {
    return $false   # user pressed "No" in the UAC prompt
  }
}

# ------------------------------------------------------------------ firewall
function Test-FirewallRule {
  try { return [bool](Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue) } catch { return $false }
}

function Show-NetworkProfileHint {
  try {
    $pub = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'Public' })
  } catch { $pub = @() }
  if ($pub.Count -gt 0) {
    $names = ($pub | ForEach-Object { $_.Name }) -join ', '
    Warn "Сеть «$names» отмечена в Windows как ОБЩЕСТВЕННАЯ. Правило файрвола действует только в ЧАСТНОЙ сети." `
         "Network '$names' is marked as PUBLIC in Windows. The firewall rule only applies to PRIVATE networks."
    Say  '    Если это ваш домашний Wi-Fi: Параметры -> Сеть и Интернет -> Wi-Fi -> (ваша сеть) -> Тип сетевого профиля: «Частная».' `
         '    If this is your home Wi-Fi: Settings -> Network & internet -> Wi-Fi -> (your network) -> Network profile type: "Private".'
  }
}

function Add-FirewallRule {
  if (Test-FirewallRule) { Ok "Правило файрвола «$RuleName» уже есть." "Firewall rule '$RuleName' already exists."; Show-NetworkProfileHint; return }
  Say "Чтобы главный ПК мог подключиться, Windows Firewall должен пропускать входящий TCP-порт $Port." `
      "For the main PC to connect, Windows Firewall must allow incoming TCP port $Port."
  Say 'Для этого нужны права администратора: Windows покажет окно «Разрешить этому приложению вносить изменения?» — нажмите «Да».' `
      'This needs administrator rights: Windows will ask "Do you want to allow this app to make changes?" — click "Yes".'
  Say '(Правило только для ЧАСТНЫХ сетей, то есть для домашнего Wi-Fi, не для кафе.)' `
      '(The rule is for PRIVATE networks only, i.e. your home Wi-Fi, not a cafe.)'
  if (-not (Ask 'Добавить правило файрвола?' 'Add the firewall rule?' $true)) {
    Warn 'Пропускаю. Без правила Argus может видеть ноду, но не подключиться (OFFLINE).' `
         'Skipped. Without the rule Argus may see the node but fail to connect (OFFLINE).'
    return
  }
  $code = "New-NetFirewallRule -DisplayName '$RuleName' -Description 'Argus LLM cluster node: llama.cpp rpc-server (home network only)' " +
          "-Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Private,Domain | Out-Null"
  if ((Invoke-Elevated $code) -and (Test-FirewallRule)) {
    Ok "Порт $Port/TCP открыт в Windows Firewall." "Port $Port/TCP is open in Windows Firewall."
  } else {
    Warn 'Не получилось добавить правило. Можно вручную (PowerShell от имени администратора):' `
         'Could not add the rule. You can do it manually (PowerShell as administrator):'
    Write-Host "    New-NetFirewallRule -DisplayName '$RuleName' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Private,Domain"
  }
  Show-NetworkProfileHint
}

# ------------------------------------------------------------------ download / pick build
function Get-File([string]$url, [string]$dest) {
  $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
  if (Test-Path $curl) {
    & $curl -fL --retry 3 -o $dest $url
    if ($LASTEXITCODE -ne 0) { throw "download failed: $url" }
  } else {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
  }
}

function Get-NvidiaDriverMajor {
  $exe = $null
  $cmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { $exe = $cmd.Path }
  if (-not $exe) {
    $p = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (Test-Path $p) { $exe = $p } else { return 0 }
  }
  try {
    $v = (& $exe --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1)
    if ("$v" -match '^\s*(\d+)') { return [int]$Matches[1] }
  } catch { }
  return 0
}

# returns @{ Zip = 'llama-b12008-bin-...zip'; Cudart = '...zip' or $null; Variant = '...' }
function Select-Build {
  $arch = $env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
  $a = 'x64'; if ($arch -eq 'ARM64') { $a = 'arm64' }
  $hasVulkan = Test-Path (Join-Path $env:SystemRoot 'System32\vulkan-1.dll')
  $nv = Get-NvidiaDriverMajor

  # Official b12008 Windows assets (checked against the GitHub release):
  #   llama-b12008-bin-win-cpu-x64.zip / -cpu-arm64.zip, llama-b12008-bin-win-vulkan-x64.zip / -vulkan-arm64.zip,
  #   llama-b12008-bin-win-cuda-12.4-x64.zip + cudart-llama-bin-win-cuda-12.4-x64.zip,
  #   llama-b12008-bin-win-cuda-13.4-x64.zip + cudart-llama-bin-win-cuda-13.4-x64.zip (also -arm64).
  # Every one of them contains ggml-rpc-server.exe at the zip root.
  $b = $Backend
  if ($b -eq 'auto') {
    if ($nv -ge 528) { $b = 'cuda' } elseif ($hasVulkan) { $b = 'vulkan' } else { $b = 'cpu' }
  }
  if ($b -eq 'cuda') {
    if ($nv -eq 0) { Warn 'nvidia-smi не найден — беру Vulkan/CPU.' 'nvidia-smi not found — using Vulkan/CPU.'; if ($hasVulkan) { $b = 'vulkan' } else { $b = 'cpu' } }
  }
  if ($b -eq 'cuda') {
    # CUDA 13.x needs driver >= 580, CUDA 12.x works from 528 (minor-version compatibility)
    $cv = '12.4'; if ($nv -ge 580 -or $a -eq 'arm64') { $cv = '13.4' }
    Say "Видеокарта NVIDIA (драйвер $nv): беру сборку CUDA $cv. Это большая загрузка (~450-600 МБ). Меньше и почти так же быстро: -Backend vulkan" `
        "NVIDIA GPU (driver $nv): using the CUDA $cv build. It is a big download (~450-600 MB). Smaller and nearly as fast: -Backend vulkan"
    return @{ Zip = "llama-$LlamaRef-bin-win-cuda-$cv-$a.zip"; Cudart = "cudart-llama-bin-win-cuda-$cv-$a.zip"; Variant = "win-$a-cuda$cv" }
  }
  if ($b -eq 'vulkan') {
    if (-not $hasVulkan) { Warn 'vulkan-1.dll не найден в System32 — обновите драйвер видеокарты. Пробую всё равно.' 'vulkan-1.dll not found in System32 — update your GPU driver. Trying anyway.' }
    return @{ Zip = "llama-$LlamaRef-bin-win-vulkan-$a.zip"; Cudart = $null; Variant = "win-$a-vulkan" }
  }
  return @{ Zip = "llama-$LlamaRef-bin-win-cpu-$a.zip"; Cudart = $null; Variant = "win-$a-cpu" }
}

function Install-Build($build) {
  $out = Join-Path $Dir ("$LlamaRef-" + $build.Variant)
  $exe = Join-Path $out 'ggml-rpc-server.exe'
  if (Test-Path $exe) { return $exe }
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  if (Test-Path $out) { Remove-Item -Recurse -Force $out }
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  $zips = @($build.Zip); if ($build.Cudart) { $zips += $build.Cudart }
  foreach ($z in $zips) {
    $tmp = Join-Path $Dir $z
    Info "Скачиваю $z …" "Downloading $z …"
    try { Get-File "$Rel/$z" $tmp } catch { Remove-Item -Force $out -Recurse -ErrorAction SilentlyContinue; Fail "Не удалось скачать $Rel/$z — проверьте интернет." "Could not download $Rel/$z — check your internet connection." }
    Expand-Archive -LiteralPath $tmp -DestinationPath $out -Force
    Remove-Item -Force $tmp
  }
  if (-not (Test-Path $exe)) {
    # older/newer llama.cpp builds called it rpc-server.exe and some zips have a sub-folder
    $found = Get-ChildItem -Path $out -Recurse -Include 'ggml-rpc-server.exe', 'rpc-server.exe' | Select-Object -First 1
    if (-not $found) { Fail 'В архиве нет ggml-rpc-server.exe.' 'ggml-rpc-server.exe is not in the archive.' }
    $exe = $found.FullName
  }
  Ok "llama.cpp $LlamaRef ($($build.Variant)) -> $out" "llama.cpp $LlamaRef ($($build.Variant)) -> $out"
  return $exe
}

# ------------------------------------------------------------------ network info / beacon
function Get-LocalIPv4 {
  $res = @()
  try {
    $res = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
      $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and
      $_.InterfaceAlias -notmatch 'vEthernet|VirtualBox|VMware|Loopback|Hyper-V|WSL|Tailscale|ZeroTier|Bluetooth'
    } | ForEach-Object { [pscustomobject]@{ IP = $_.IPAddress; Prefix = [int]$_.PrefixLength; If = $_.InterfaceAlias } })
  } catch {
    try {
      foreach ($ip in [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName())) {
        if ($ip.AddressFamily -eq 'InterNetwork' -and -not $ip.ToString().StartsWith('127.')) {
          $res += [pscustomobject]@{ IP = $ip.ToString(); Prefix = 24; If = '?' }
        }
      }
    } catch { $res = @() }
  }
  return $res
}

function Get-BroadcastAddress([string]$ip, [int]$prefix) {
  $b = ([Net.IPAddress]::Parse($ip)).GetAddressBytes()
  [Array]::Reverse($b)
  $n = [BitConverter]::ToUInt32($b, 0)
  $mask = [uint32]0
  if ($prefix -gt 0) { $mask = [uint32]([uint64][uint32]::MaxValue -shl (32 - $prefix) -band [uint32]::MaxValue) }
  $bc = ($n -band $mask) -bor (-bnot $mask -band [uint32]::MaxValue)
  $o = [BitConverter]::GetBytes([uint32]$bc)
  [Array]::Reverse($o)
  return ([Net.IPAddress]$o).ToString()
}

function Get-MemoryMb {
  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    return @([int]([uint64]$os.TotalVisibleMemorySize / 1024), [int]([uint64]$os.FreePhysicalMemory / 1024))
  } catch { return @(0, 0) }
}

function ConvertTo-JsonString([string]$s) {
  return '"' + ($s -replace '\\', '\\' -replace '"', '\"' -replace "[\r\n\t]", ' ') + '"'
}

function Show-Banner($ips) {
  $first = '<IP>'; if ($ips.Count -gt 0) { $first = $ips[0].IP }
  Write-Host ''
  Write-Host '  ==============================================================' -ForegroundColor Green
  Write-Host ('   ' + (T 'ГОТОВО! Этот компьютер — нода Argus.' 'DONE! This computer is now an Argus node.')) -ForegroundColor Green
  Write-Host '  ==============================================================' -ForegroundColor Green
  Write-Host ''
  Say 'IP-адрес этого компьютера:' "This computer's IP address:"
  if ($ips.Count -eq 0) { Write-Host '      ?' }
  foreach ($i in $ips) { Write-Host ("      {0}  ({1})" -f $i.IP, $i.If) -ForegroundColor White }
  Write-Host ''
  Say 'Теперь на ГЛАВНОМ компьютере (где установлен Argus):' 'Now, on the MAIN computer (where Argus is installed):'
  Say '  1. Откройте Argus -> вкладка «Cluster».' '  1. Open Argus -> the "Cluster" tab.'
  Say '  2. В списке «Найдено в сети» найдите этот компьютер и нажмите «Добавить».' '  2. In "Найдено в сети" (Found on network) find this computer and click "Добавить" (Add).'
  Say '  3. Нет в списке? Нажмите «Добавить ноду по IP» и введите:' '  3. Not in the list? Click "Добавить ноду по IP" (Add node by IP) and type:'
  Write-Host ''
  Write-Host ("         {0}:{1}" -f $first, $Port) -ForegroundColor White
  Write-Host ''
  Say 'Оба компьютера должны быть в одной домашней Wi-Fi сети (не гостевой).' 'Both computers must be on the same home Wi-Fi network (not a guest network).'
  Warn "У ноды нет пароля: только домашняя сеть, не открывайте порт $Port в интернет." "The node has no password: home network only, never expose port $Port to the internet."
  Write-Host ''
}

# ------------------------------------------------------------------ autostart (Scheduled Task) / uninstall
function Install-Autostart {
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $self = Join-Path $Dir 'argus-node-windows.ps1'
  if ($PSCommandPath -and ((Resolve-Path $PSCommandPath).Path -ne $self)) {
    Copy-Item -LiteralPath $PSCommandPath -Destination $self -Force
  } elseif (-not (Test-Path $self)) {
    Get-File $RawScript $self
  }
  $argList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$self`" -Background -Port $Port -Backend $Backend -Lang $Lang"
  if ($BeaconTarget) { $argList += " -BeaconTarget `"$BeaconTarget`"" }
  if ($Name -ne $env:COMPUTERNAME) { $argList += " -Name `"$($Name -replace '"', '')`"" }
  $user = "$env:USERDOMAIN\$env:USERNAME"
  $registered = $false
  try {
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argList -WorkingDirectory $Dir
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                 -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
      -Description 'Argus LLM cluster node (llama.cpp rpc-server + beacon)' -Force | Out-Null
    $registered = $true
  } catch {
    Warn "Не удалось создать задачу в Планировщике ($($_.Exception.Message)). Кладу ярлык в «Автозагрузку»." `
         "Could not create the Scheduled Task ($($_.Exception.Message)). Using the Startup folder instead."
  }
  if ($registered) {
    Ok "Автозапуск при входе в Windows: Планировщик заданий -> «$TaskName»." "Autostart at logon: Task Scheduler -> '$TaskName'."
    Start-ScheduledTask -TaskName $TaskName
  } else {
    $startup = [Environment]::GetFolderPath('Startup')
    $cmd = Join-Path $startup 'Argus Node.cmd'
    Set-Content -LiteralPath $cmd -Encoding ASCII -Value "@start `"`" /min powershell.exe $argList"
    Ok "Автозапуск: $cmd" "Autostart: $cmd"
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden
  }
  Say "Журнал ноды: $Dir\node.log" "Node log: $Dir\node.log"
}

function Stop-NodeProcess {
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
  # the background PowerShell loop first (otherwise it restarts rpc-server), then rpc-server itself
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine -like '*argus-node-windows.ps1*' -and $_.CommandLine -like '*-Background*' -and $_.ProcessId -ne $PID } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  Get-Process -Name 'ggml-rpc-server', 'rpc-server' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
}

function Uninstall-Node {
  Info 'Удаляю ноду Argus…' 'Removing the Argus node…'
  Stop-NodeProcess
  try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
  $cmd = Join-Path ([Environment]::GetFolderPath('Startup')) 'Argus Node.cmd'
  if (Test-Path $cmd) { Remove-Item -Force $cmd }
  Ok 'Автозапуск выключен.' 'Autostart removed.'
  if (Test-FirewallRule) {
    Say 'Удаляю правило файрвола (Windows спросит права администратора)…' 'Removing the firewall rule (Windows will ask for administrator rights)…'
    if (Invoke-Elevated "Remove-NetFirewallRule -DisplayName '$RuleName'") { Ok 'Правило файрвола удалено.' 'Firewall rule removed.' }
    else { Warn "Не получилось. Вручную (от администратора): Remove-NetFirewallRule -DisplayName '$RuleName'" "Failed. Manually (as admin): Remove-NetFirewallRule -DisplayName '$RuleName'" }
  }
  if (Test-Path $Dir) {
    if (Ask "Удалить папку $Dir (llama.cpp, кэш)?" "Delete $Dir (llama.cpp, cache)?" $true) {
      Start-Sleep -Milliseconds 500
      Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue
      if (Test-Path $Dir) { Warn "Часть файлов занята, удалите папку вручную: $Dir" "Some files are busy, delete the folder manually: $Dir" }
      else { Ok 'Папка удалена.' 'Folder deleted.' }
    }
  }
  Ok 'Нода Argus удалена. Не забудьте удалить её и в Argus (Cluster).' 'Argus node removed. Remember to remove it in Argus (Cluster) too.'
}

# ------------------------------------------------------------------ run: rpc-server + beacon, restarted if it dies
function Start-Node {
  New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'cache') | Out-Null

  $listening = $null
  try { $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue } catch { }
  if ($listening) {
    $owner = ''
    try { $owner = (Get-Process -Id @($listening)[0].OwningProcess -ErrorAction SilentlyContinue).Path } catch { }
    Fail "Порт $Port уже занят ($owner). Нода уже запущена (например, автозапуском)? Остановить: -Uninstall или Диспетчер задач." `
         "Port $Port is already in use ($owner). Is the node already running (e.g. autostart)? Stop it: -Uninstall or Task Manager."
  }

  $variant = 'custom'
  if ($env:ARGUS_RPC_BIN) {
    $exe = $env:ARGUS_RPC_BIN
  } else {
    $build = Select-Build
    $exe = Install-Build $build
    $variant = $build.Variant
  }
  if (-not (Test-Path $exe)) { Fail "rpc-server не найден: $exe" "rpc-server not found: $exe" }

  $ips = @(Get-LocalIPv4)
  $targets = New-Object System.Collections.Generic.List[string]
  $targets.Add('255.255.255.255')
  foreach ($i in $ips) { try { $bc = Get-BroadcastAddress $i.IP $i.Prefix; if (-not $targets.Contains($bc)) { $targets.Add($bc) } } catch { } }
  foreach ($t in ($BeaconTarget -split '[,; ]')) { if ($t) { $targets.Add($t) } }

  if (-not $Background) { Show-Banner $ips }
  Log ("{0} · {1} · {2} {3} · {4} {5}" -f $Name, $variant, $Threads, (T 'потоков' 'threads'), (T 'порт' 'port'), $Port)
  Log (T '!! без пароля и шифрования — только закрытая домашняя сеть' '!! no password, no encryption — closed home network only')
  if (-not $Background) { Say 'Нода работает, пока открыто это окно. Остановить: Ctrl+C.' 'The node runs while this window is open. Stop: Ctrl+C.' 'Cyan' }

  $udp = New-Object System.Net.Sockets.UdpClient
  $udp.EnableBroadcast = $true
  $proc = $null
  $env:LLAMA_CACHE = Join-Path $Dir 'cache'
  $rpcArgs = @('-H', '0.0.0.0', '-p', "$Port", '-t', "$Threads", '-c')
  $nameJson = ConvertTo-JsonString $Name
  $variantJson = ConvertTo-JsonString $variant
  $memTick = 0; $mem = @(0, 0)
  try {
    while ($true) {
      if ($null -eq $proc -or $proc.HasExited) {
        if ($null -ne $proc) {
          Log ((T 'rpc-server завершился (код {0}) — перезапуск через 3 с' 'rpc-server exited (code {0}) — restarting in 3 s') -f $proc.ExitCode)
          Start-Sleep -Seconds 3
        }
        $sp = @{ FilePath = $exe; ArgumentList = $rpcArgs; WorkingDirectory = (Split-Path $exe); PassThru = $true }
        if ($Background) {
          $sp.WindowStyle = 'Hidden'
          $sp.RedirectStandardOutput = Join-Path $Dir 'rpc-server.out.log'
          $sp.RedirectStandardError  = Join-Path $Dir 'rpc-server.err.log'
        } else {
          $sp.NoNewWindow = $true
        }
        $proc = Start-Process @sp
        $null = $proc.Handle   # PS 5.1: without a cached handle ExitCode stays empty
        Start-Sleep -Milliseconds 500
      }
      if (-not $proc.HasExited) {
        # no beacon while rpc-server is down -> Argus marks the node OFFLINE after 10 s
        if ($memTick -le 0) { $mem = Get-MemoryMb; $memTick = 5 }   # CIM is slow-ish: every 10 s is enough
        $memTick--
        $msg = '{{"argus":"node","v":1,"name":{0},"port":{1},"ram_mb":{2},"free_mb":{3},"variant":{4}}}' -f $nameJson, $Port, $mem[0], $mem[1], $variantJson
        $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
        foreach ($t in $targets) {
          try { [void]$udp.Send($bytes, $bytes.Length, $t, $BeaconPort) } catch { }
        }
      }
      Start-Sleep -Seconds 2
    }
  } finally {
    # Ctrl+C lands here too
    if ($null -ne $proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
    $udp.Close()
    Log (T 'нода остановлена' 'node stopped')
  }
}

# ------------------------------------------------------------------ main
try {
  if ($Background) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    try { Start-Transcript -Path (Join-Path $Dir 'node.log') -Force | Out-Null } catch { }
  } else {
    Write-Host ''
    Write-Host (T 'Argus — нода для Windows' 'Argus — Windows node') -ForegroundColor Cyan
    Write-Host ''
  }

  if ($Uninstall)    { Uninstall-Node; return }
  if ($OpenFirewall) { Add-FirewallRule; return }

  if (-not $Background) { Add-FirewallRule }

  if ($Install) {
    if (-not $env:ARGUS_RPC_BIN) { [void](Install-Build (Select-Build)) }   # download now, in the visible window
    Stop-NodeProcess
    Install-Autostart
    Show-Banner @(Get-LocalIPv4)
    Say "Остановить и удалить: argus-node-windows.cmd -Uninstall" "Stop and remove: argus-node-windows.cmd -Uninstall"
    return
  }

  Start-Node
} catch {
  if ("$_" -ne 'argus-node: stopped') { Write-Host ("[argus-node] " + (T 'ОШИБКА: ' 'ERROR: ') + $_) -ForegroundColor Red }
  if ($Background) { Start-Sleep -Seconds 5 }   # let the Scheduled Task restart policy kick in
  exit 1
} finally {
  if ($Background) { try { Stop-Transcript | Out-Null } catch { } }
}
