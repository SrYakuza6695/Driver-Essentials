<#
  ____        __   __     _
 / ___| _ __  \ \ / /__ _| | ___   _ ____ _
 \___ \| '__|  \ V / _` | |/ / | | |_  / _` |
  ___) | |      | | (_| |   <| |_| |/ / (_| |
 |____/|_|      |_|\__,_|_|\_\\__,_/___\__,_|

 Driver Essentials
 Perfil do dono: SrYakuza6695

 AVISO:
 Este codigo e fornecido para uso pessoal/tecnico.
 E proibido vender, revender, empacotar comercialmente ou distribuir este codigo
 como produto pago sem autorizacao expressa do perfil SrYakuza6695.

O script detecta o PC, instala drivers pelo Windows Update/Microsoft Update
e tenta ferramentas oficiais do fabricante e da GPU quando possivel.
Nao usa driver packs de terceiros.
#>

[CmdletBinding()]
param(
    [switch]$DownloadOnly,
    [switch]$AutoReboot,
    [switch]$SkipVendorTools,
    [switch]$SkipGpuInstallers,
    [switch]$SkipRestorePoint
)

$ErrorActionPreference = 'Stop'
$script:MicrosoftUpdateServiceId = '7971f918-a847-4430-9279-4a52d1efe18d'
$script:ToolName = 'Driver Essentials'

function Show-Banner {
    Clear-Host
    Write-Host @'
  ____        __   __     _
 / ___| _ __  \ \ / /__ _| | ___   _ ____ _
 \___ \| '__|  \ V / _` | |/ / | | |_  / _` |
  ___) | |      | | (_| |   <| |_| |/ / (_| |
 |____/|_|      |_|\__,_|_|\_\\__,_/___\__,_|

        Driver Essentials
'@ -ForegroundColor Cyan
    Write-Host 'Perfil do dono: SrYakuza6695' -ForegroundColor Yellow
    Write-Host 'Proibido vender sem autorizacao expressa do perfil SrYakuza6695.' -ForegroundColor Red
    Write-Host ''
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Good {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-SoftWarning {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SupportedWindows {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $caption = [string]$os.Caption

    if ($caption -notmatch 'Windows 10|Windows 11') {
        throw "Sistema nao suportado: $caption. Este script foi feito para Windows 10 e Windows 11."
    }

    Write-Good "Sistema detectado: $caption build $($os.BuildNumber)"
}

function Start-DriverLog {
    $script:LogDir = Join-Path $env:ProgramData 'DriverEssentials\DriverUpdate'
    New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:TranscriptPath = Join-Path $script:LogDir "Driver-Essentials-$stamp.log"
    Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
    Write-Host "Log: $script:TranscriptPath" -ForegroundColor DarkGray
}

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-SoftWarning "Nao foi possivel ajustar TLS 1.2. Detalhe: $($_.Exception.Message)"
    }
}

function New-SafeRestorePoint {
    if ($SkipRestorePoint) {
        Write-Host 'Ponto de restauracao ignorado por parametro.' -ForegroundColor DarkGray
        return
    }

    try {
        Write-Step 'Criando ponto de restauracao'
        Checkpoint-Computer -Description $script:ToolName -RestorePointType 'MODIFY_SETTINGS'
        Write-Good 'Ponto de restauracao criado.'
    }
    catch {
        Write-SoftWarning "Nao foi possivel criar ponto de restauracao. Continuando. Detalhe: $($_.Exception.Message)"
    }
}

function Get-HardwareProfile {
    $computer = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $baseBoard = Get-CimInstance Win32_BaseBoard
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $video = @(Get-CimInstance Win32_VideoController | Select-Object Name, AdapterCompatibility, DriverVersion, PNPDeviceID)
    $network = @(Get-CimInstance Win32_NetworkAdapter |
        Where-Object { $_.PhysicalAdapter -eq $true } |
        Select-Object Name, Manufacturer, PNPDeviceID)

    [pscustomobject]@{
        ComputerManufacturer = $computer.Manufacturer
        ComputerModel        = $computer.Model
        BaseBoardManufacturer = $baseBoard.Manufacturer
        BaseBoardProduct     = $baseBoard.Product
        BiosManufacturer     = $bios.Manufacturer
        BiosVersion          = ($bios.SMBIOSBIOSVersion -join ' ')
        SerialNumber         = $bios.SerialNumber
        OS                   = $os.Caption
        OSBuild              = $os.BuildNumber
        Processor            = $processor.Name
        VideoControllers     = $video
        NetworkAdapters      = $network
    }
}

function Export-HardwareProfile {
    param([Parameter(Mandatory)]$Profile)

    $hardwarePath = Join-Path $script:LogDir 'hardware-profile.json'
    $Profile | ConvertTo-Json -Depth 6 | Out-File -FilePath $hardwarePath -Encoding UTF8
    Write-Host "Perfil do PC salvo em: $hardwarePath" -ForegroundColor DarkGray
}

function Show-HardwareProfile {
    param([Parameter(Mandatory)]$Profile)

    Write-Step 'PC detectado'
    Write-Host "Fabricante: $($Profile.ComputerManufacturer)"
    Write-Host "Modelo:     $($Profile.ComputerModel)"
    Write-Host "Placa-mae:  $($Profile.BaseBoardManufacturer) $($Profile.BaseBoardProduct)"
    Write-Host "Processador:$($Profile.Processor)"

    if ($Profile.VideoControllers.Count -gt 0) {
        Write-Host 'Video:'
        $Profile.VideoControllers | ForEach-Object {
            Write-Host "  - $($_.Name) [$($_.AdapterCompatibility)]"
        }
    }
}

function Add-MicrosoftUpdateServiceNative {
    Write-Step 'Ativando Microsoft Update'
    try {
        $serviceManager = New-Object -ComObject Microsoft.Update.ServiceManager
        $serviceManager.ClientApplicationID = $script:ToolName
        $serviceManager.AddService2($script:MicrosoftUpdateServiceId, 7, '') | Out-Null
        Write-Good 'Microsoft Update ativado.'
    }
    catch {
        Write-SoftWarning "Microsoft Update pode ja estar ativo ou foi bloqueado pela politica do sistema. Detalhe: $($_.Exception.Message)"
    }
}

function Convert-WUResultCode {
    param([Parameter(Mandatory)]$Code)

    switch ([int]$Code) {
        0 { 'Nao iniciado' }
        1 { 'Em andamento' }
        2 { 'Sucesso' }
        3 { 'Sucesso com avisos' }
        4 { 'Falhou' }
        5 { 'Cancelado' }
        default { "Codigo $Code" }
    }
}

function New-WindowsUpdateSession {
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = $script:ToolName
    return $session
}

function Get-NativeDriverUpdates {
    param([Parameter(Mandatory)]$Session)

    Write-Step 'Procurando drivers pelo Windows Update'

    $searcher = $Session.CreateUpdateSearcher()
    try {
        $searcher.ServerSelection = 3
        $searcher.ServiceID = $script:MicrosoftUpdateServiceId
    }
    catch {
        Write-SoftWarning "Nao foi possivel forcar a origem Microsoft Update. Tentando a origem padrao. Detalhe: $($_.Exception.Message)"
    }

    $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
    $updates = @()

    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $updates += $result.Updates.Item($i)
    }

    return $updates
}

function Show-DriverUpdates {
    param([Parameter(Mandatory)][array]$Updates)

    if ($Updates.Count -eq 0) {
        Write-Host 'Nenhum driver novo encontrado pelo Windows/Microsoft Update.' -ForegroundColor Yellow
        return
    }

    Write-Good "Drivers encontrados: $($Updates.Count)"
    $rows = foreach ($update in $Updates) {
        [pscustomobject]@{
            TamanhoMB = [math]::Round(($update.MaxDownloadSize / 1MB), 2)
            Baixado   = $update.IsDownloaded
            Titulo    = $update.Title
        }
    }

    $rows | Format-Table -AutoSize
}

function Invoke-NativeDriverUpdates {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][array]$Updates
    )

    if ($Updates.Count -eq 0) {
        return
    }

    $downloadCollection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($update in $Updates) {
        if (-not $update.EulaAccepted) {
            $update.AcceptEula()
        }
        [void]$downloadCollection.Add($update)
    }

    Write-Step 'Baixando drivers encontrados'
    $downloader = $Session.CreateUpdateDownloader()
    $downloader.Updates = $downloadCollection
    $downloadResult = $downloader.Download()
    Write-Host "Resultado do download: $(Convert-WUResultCode $downloadResult.ResultCode)"

    if ($DownloadOnly) {
        Write-Host 'Modo DownloadOnly ativo. Drivers baixados sem instalar.' -ForegroundColor Yellow
        return
    }

    $installCollection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($update in $Updates) {
        if ($update.IsDownloaded) {
            [void]$installCollection.Add($update)
        }
        else {
            Write-SoftWarning "Driver nao baixado e sera ignorado: $($update.Title)"
        }
    }

    if ($installCollection.Count -eq 0) {
        Write-SoftWarning 'Nenhum driver ficou pronto para instalacao.'
        return
    }

    Write-Step 'Instalando drivers'
    $installer = $Session.CreateUpdateInstaller()
    $installer.Updates = $installCollection
    $installer.AllowSourcePrompts = $false
    $installer.ForceQuiet = $true
    $installResult = $installer.Install()

    Write-Host "Resultado da instalacao: $(Convert-WUResultCode $installResult.ResultCode)"

    if ($installResult.RebootRequired) {
        $script:RebootRequiredByUpdate = $true
    }
}

function Install-PSWindowsUpdateFallback {
    Write-Step 'Tentando fallback com PSWindowsUpdate'

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }

        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        $oldPolicy = $null
        if ($repo) {
            $oldPolicy = $repo.InstallationPolicy
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        try {
            Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force -AllowClobber
        }
        finally {
            if ($oldPolicy) {
                Set-PSRepository -Name PSGallery -InstallationPolicy $oldPolicy
            }
        }
    }

    Import-Module PSWindowsUpdate -Force

    try {
        Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null
    }
    catch {
        Write-SoftWarning "Nao foi possivel adicionar Microsoft Update pelo fallback. Detalhe: $($_.Exception.Message)"
    }

    $rebootSwitch = if ($AutoReboot) { @{ AutoReboot = $true } } else { @{ IgnoreReboot = $true } }

    if ($DownloadOnly) {
        Download-WindowsUpdate -MicrosoftUpdate -UpdateType Driver -AcceptAll -Confirm:$false @rebootSwitch
    }
    else {
        Install-WindowsUpdate -MicrosoftUpdate -UpdateType Driver -AcceptAll -Confirm:$false @rebootSwitch
    }
}

function Invoke-WindowsDriverUpdates {
    try {
        Add-MicrosoftUpdateServiceNative
        $session = New-WindowsUpdateSession
        $updates = @(Get-NativeDriverUpdates -Session $session)
        Show-DriverUpdates -Updates $updates
        Invoke-NativeDriverUpdates -Session $session -Updates $updates
    }
    catch {
        Write-SoftWarning "Metodo nativo do Windows Update falhou. Detalhe: $($_.Exception.Message)"
        try {
            Install-PSWindowsUpdateFallback
        }
        catch {
            throw "Falha ao instalar drivers pelo metodo nativo e pelo fallback. Detalhe: $($_.Exception.Message)"
        }
    }
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-CommandAvailable -Name 'winget')) {
        Write-SoftWarning "winget nao encontrado. Pulando $Name."
        return $false
    }

    Write-Host "Instalando/verificando $Name pelo winget..." -ForegroundColor Cyan
    $args = @(
        'install',
        '--id', $Id,
        '-e',
        '--source', 'winget',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    & winget @args

    if ($LASTEXITCODE -eq 0) {
        Write-Good "$Name pronto."
        return $true
    }

    Write-SoftWarning "$Name nao foi instalado automaticamente. Codigo: $LASTEXITCODE"
    return $false
}

function Get-VendorToolPlan {
    param([Parameter(Mandatory)]$Profile)

    $text = @(
        $Profile.ComputerManufacturer,
        $Profile.BaseBoardManufacturer,
        $Profile.BiosManufacturer,
        $Profile.ComputerModel
    ) -join ' '

    $tools = @()

    if ($text -match '(?i)dell') {
        $tools += [pscustomobject]@{ Id = 'Dell.CommandUpdate'; Name = 'Dell Command Update'; Kind = 'Dell' }
    }
    elseif ($text -match '(?i)lenovo') {
        $tools += [pscustomobject]@{ Id = 'Lenovo.SystemUpdate'; Name = 'Lenovo System Update'; Kind = 'Lenovo' }
    }
    elseif ($text -match '(?i)hp|hewlett') {
        $tools += [pscustomobject]@{ Id = 'HPInc.HPSupportAssistant'; Name = 'HP Support Assistant'; Kind = 'HP' }
    }

    $deviceText = @(
        $Profile.Processor,
        ($Profile.VideoControllers | ForEach-Object { "$($_.Name) $($_.AdapterCompatibility)" }),
        ($Profile.NetworkAdapters | ForEach-Object { "$($_.Name) $($_.Manufacturer)" })
    ) -join ' '

    if ($deviceText -match '(?i)intel') {
        $tools += [pscustomobject]@{ Id = 'Intel.IntelDriverAndSupportAssistant'; Name = 'Intel Driver & Support Assistant'; Kind = 'Intel' }
    }

    return $tools
}

function Invoke-DellCommandUpdate {
    $paths = @(
        "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe",
        "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
    )

    $dcu = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $dcu) {
        Write-SoftWarning 'Dell Command Update instalado, mas dcu-cli.exe nao foi encontrado.'
        return
    }

    Write-Step 'Rodando Dell Command Update'
    & $dcu /scan -silent
    & $dcu /applyUpdates -silent -reboot=disable

    if ($LASTEXITCODE -eq 0) {
        Write-Good 'Dell Command Update terminou.'
    }
    else {
        Write-SoftWarning "Dell Command Update retornou codigo $LASTEXITCODE."
    }
}

function Invoke-VendorTools {
    param([Parameter(Mandatory)]$Profile)

    if ($SkipVendorTools) {
        Write-Host 'Ferramentas oficiais do fabricante ignoradas por parametro.' -ForegroundColor DarkGray
        return
    }

    Write-Step 'Verificando ferramentas oficiais do fabricante'
    $tools = @(Get-VendorToolPlan -Profile $Profile)

    if ($tools.Count -eq 0) {
        Write-Host 'Nenhuma ferramenta oficial extra foi detectada para este PC.' -ForegroundColor Yellow
        return
    }

    foreach ($tool in $tools) {
        $installed = Invoke-WingetInstall -Id $tool.Id -Name $tool.Name

        if ($installed -and $tool.Kind -eq 'Dell' -and -not $DownloadOnly) {
            Invoke-DellCommandUpdate
        }
        elseif ($installed -and ($tool.Kind -in @('Lenovo', 'HP', 'Intel'))) {
            Write-Host "$($tool.Name) foi instalado/verificado. Se ele abrir uma etapa propria do fabricante, siga a interface oficial." -ForegroundColor Yellow
        }
    }
}

function Get-GpuVendorPlan {
    param([Parameter(Mandatory)]$Profile)

    $gpuText = ($Profile.VideoControllers | ForEach-Object {
        "$($_.Name) $($_.AdapterCompatibility) $($_.PNPDeviceID)"
    }) -join ' '

    $tools = @()

    if ($gpuText -match '(?i)nvidia|geforce|quadro|\brtx\b|\bgtx\b') {
        $tools += [pscustomobject]@{
            Name = 'NVIDIA App'
            PageUrl = 'https://www.nvidia.com/en-us/software/nvidia-app/'
            LinkRegex = '(?<url>https://us\.download\.nvidia\.com/nvapp/client/[^"''<>\s]+/NVIDIA_app_[^"''<>\s]+\.exe)'
        }
    }

    if ($gpuText -match '(?i)\bamd\b|advanced micro devices|radeon|\brx\s?[0-9]|vega') {
        $tools += [pscustomobject]@{
            Name = 'AMD Auto-Detect and Install'
            PageUrl = 'https://www.amd.com/en/support/download/drivers.html'
            LinkRegex = '(?<url>https://drivers\.amd\.com/drivers/installer/[^"''<>\s]+amd-software-adrenalin-edition[^"''<>\s]+\.exe)'
        }
    }

    return $tools
}

function Resolve-OfficialDownloadLink {
    param(
        [Parameter(Mandatory)][string]$PageUrl,
        [Parameter(Mandatory)][string]$LinkRegex,
        [Parameter(Mandatory)][string]$Name
    )

    Write-Host "Procurando link oficial de $Name..." -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri $PageUrl -UseBasicParsing -MaximumRedirection 5
    $match = [regex]::Match($response.Content, $LinkRegex, [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if (-not $match.Success) {
        throw "Nao foi possivel encontrar o link oficial de $Name em $PageUrl."
    }

    $url = [Net.WebUtility]::HtmlDecode($match.Groups['url'].Value)
    if ($url -match '^//') {
        $url = "https:$url"
    }
    elseif ($url -notmatch '^https?://') {
        $url = ([Uri]::new([Uri]$PageUrl, $url)).AbsoluteUri
    }

    return $url
}

function Save-OfficialInstaller {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Url
    )

    $installerDir = Join-Path $script:LogDir 'Installers'
    New-Item -Path $installerDir -ItemType Directory -Force | Out-Null

    $fileName = [IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = ($Name -replace '[^a-zA-Z0-9.-]', '-') + '.exe'
    }

    $destination = Join-Path $installerDir $fileName
    Write-Host "Baixando $Name de fonte oficial..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $destination
    Write-Host "$Name salvo em: $destination" -ForegroundColor DarkGray

    return $destination
}

function Invoke-OfficialGpuInstallers {
    param([Parameter(Mandatory)]$Profile)

    if ($SkipGpuInstallers) {
        Write-Host 'Instaladores oficiais de GPU ignorados por parametro.' -ForegroundColor DarkGray
        return
    }

    Write-Step 'Verificando drivers completos AMD/NVIDIA'
    $tools = @(Get-GpuVendorPlan -Profile $Profile)

    if ($tools.Count -eq 0) {
        Write-Host 'Nenhuma GPU AMD/NVIDIA foi detectada para instalador completo.' -ForegroundColor Yellow
        return
    }

    foreach ($tool in $tools) {
        try {
            $url = Resolve-OfficialDownloadLink -PageUrl $tool.PageUrl -LinkRegex $tool.LinkRegex -Name $tool.Name
            $installer = Save-OfficialInstaller -Name $tool.Name -Url $url

            if ($DownloadOnly) {
                Write-Host "$($tool.Name) baixado. Modo DownloadOnly ativo, nao vou abrir o instalador." -ForegroundColor Yellow
                continue
            }

            Write-Host "Abrindo $($tool.Name). Siga o instalador oficial para concluir o driver completo." -ForegroundColor Yellow
            $process = Start-Process -FilePath $installer -Wait -PassThru

            if ($process.ExitCode -eq 0 -or $null -eq $process.ExitCode) {
                Write-Good "$($tool.Name) finalizado ou encaminhado para o instalador oficial."
            }
            else {
                Write-SoftWarning "$($tool.Name) retornou codigo $($process.ExitCode). Confira a janela/log do instalador."
            }
        }
        catch {
            Write-SoftWarning "Nao foi possivel baixar/abrir $($tool.Name). Detalhe: $($_.Exception.Message)"
        }
    }
}

function Invoke-DeviceRescan {
    Write-Step 'Reescaneando dispositivos Plug and Play'
    try {
        pnputil /scan-devices | Out-Host
    }
    catch {
        Write-SoftWarning "Nao foi possivel executar pnputil /scan-devices. Detalhe: $($_.Exception.Message)"
    }
}

function Export-DriverInventory {
    $inventory = Join-Path $script:LogDir 'driver-inventory.csv'
    Get-CimInstance Win32_PnPSignedDriver |
        Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName |
        Sort-Object DeviceName |
        Export-Csv -Path $inventory -NoTypeInformation -Encoding UTF8

    Write-Host "Inventario de drivers salvo em: $inventory" -ForegroundColor DarkGray
}

function Show-ProblemDevices {
    try {
        $problemDevices = @(Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' })
        $problemPath = Join-Path $script:LogDir 'problem-devices.csv'

        $problemDevices |
            Select-Object Status, Class, FriendlyName, InstanceId |
            Export-Csv -Path $problemPath -NoTypeInformation -Encoding UTF8

        if ($problemDevices.Count -gt 0) {
            Write-Step 'Dispositivos que ainda precisam de atencao'
            $problemDevices | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize
            Write-Host "Relatorio salvo em: $problemPath" -ForegroundColor DarkGray
        }
        else {
            Write-Good 'Nenhum dispositivo com problema aparente foi encontrado.'
        }
    }
    catch {
        Write-SoftWarning "Nao foi possivel listar dispositivos com problema. Detalhe: $($_.Exception.Message)"
    }
}

function Test-RebootPending {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    )

    foreach ($path in $paths) {
        if ($path -like '*Session Manager') {
            $value = Get-ItemProperty -Path $path -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($value) {
                return $true
            }
        }
        elseif (Test-Path $path) {
            return $true
        }
    }

    return $false
}

try {
    Show-Banner

    if (-not (Test-IsAdministrator)) {
        throw 'Abra o PowerShell como Administrador ou use o comando de cola-e-roda que abre UAC automaticamente.'
    }

    Test-SupportedWindows
    Start-DriverLog
    Enable-Tls12
    New-SafeRestorePoint

    $profile = Get-HardwareProfile
    Export-HardwareProfile -Profile $profile
    Show-HardwareProfile -Profile $profile

    Invoke-DeviceRescan
    Invoke-WindowsDriverUpdates
    Invoke-VendorTools -Profile $profile
    Invoke-OfficialGpuInstallers -Profile $profile
    Invoke-DeviceRescan
    Export-DriverInventory
    Show-ProblemDevices

    if ($AutoReboot -and (Test-RebootPending -or $script:RebootRequiredByUpdate)) {
        Write-Step 'Reiniciando para concluir'
        Restart-Computer -Force
    }
    elseif (Test-RebootPending -or $script:RebootRequiredByUpdate) {
        Write-Host ''
        Write-Host 'Reinicializacao pendente detectada. Reinicie o PC para concluir os drivers.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Good 'Finalizado pelo Driver Essentials.'
}
catch {
    Write-Host ''
    Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}
