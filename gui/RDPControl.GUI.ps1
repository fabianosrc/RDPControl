#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows Forms GUI for the RDPControl PowerShell module (Turkish / English).

.DESCRIPTION
    Wraps the RDPControl cmdlets in a tabbed desktop interface:
    Setup, Status, Port & Service, Session Mode, Users, Sessions, Snapshots, Watchdog.
    Setup installs and repairs the RDPControl environment from the GUI.
    Every state-changing action asks for confirmation first and writes its
    result to the log panel at the bottom of the window.

.EXAMPLE
    .\gui\RDPControl.GUI.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\RDPControl.psd1') -Force

#region Language

$script:Lang = 'tr'

$script:Strings = @{
    tr = @{
        app_title            = 'RDPControl'
        app_title_noadmin    = 'RDPControl (yönetici değil - değişiklikler başarısız olur)'
        title_confirm        = 'Onay'
        title_error          = 'Hata'
        btn_refresh          = 'Yenile'
        last_result          = 'Son sonuç:'
        lang_label           = 'Dil:'
        log_completed        = '{0} tamamlandı.'
        log_failed           = '{0} başarısız: {1}'
        log_ready            = 'RDPControl GUI hazır.'
        log_not_elevated     = 'Bu oturum yönetici değil. PowerShell''i yönetici olarak yeniden başlatın.'
        log_not_init         = 'RDPControl ortamı henüz kurulmadı. Kurulum sekmesini kullanın.'
        tab_setup            = 'Kurulum'
        tab_status           = 'Durum'
        tab_port             = 'Port ve Servis'
        tab_mode             = 'Oturum Modu'
        tab_users            = 'Kullanıcılar'
        tab_sessions         = 'Oturumlar'
        tab_snapshots        = 'Snapshot''lar'
        tab_watchdog         = 'Watchdog'
        setup_intro          = 'RDPControl''ün kullanılabilmesi için ortamının bir kez kurulması gerekir. Kontrol edip eksikleri kurabilir veya onarabilirsiniz.'
        setup_check          = 'Kontrol et'
        setup_install        = 'Kurulumu başlat'
        setup_repair         = 'Eksikleri onar'
        setup_snapshot       = 'Kurulumdan sonra termsrv.dll snapshot''ı al'
        setup_install_confirm = 'RDPControl ortamı kurulsun mu? (%ProgramData%\RDPControl klasörü ve veritabanı oluşturulur)'
        setup_repair_confirm = 'Eksik bileşenler onarılsın mı? Mevcut veriler korunur.'
        setup_state_ready    = 'Durum: Ortam hazır.'
        setup_state_not_ready = 'Durum: Ortam kurulu değil. Devam etmek için "Kurulumu başlat" düğmesine basın.'
        setup_need_admin     = 'Kurulum için yönetici olarak çalıştırmanız gerekir.'
        col_item             = 'Öğe'
        col_result           = 'Sonuç'
        chk_admin            = 'Yönetici yetkisi'
        chk_ps               = 'PowerShell sürümü'
        chk_module           = 'RDPControl modülü'
        chk_lib              = 'SQLite kütüphanesi'
        chk_env              = 'Ortam yapılandırması (environment.json)'
        chk_db               = 'Veritabanı (rdpcontrol.db)'
        res_ok               = 'Tamam'
        res_missing          = 'Eksik'
        log_setup_install    = 'Ortam kurulumu'
        log_setup_repair     = 'Ortam onarımı'
        log_setup_snapshot   = 'Kurulum sonrası snapshot'
        st_setting           = 'Ayar'
        st_value             = 'Değer'
        st_env               = 'Ortam'
        st_env_missing       = 'Kurulu değil'
        st_datadir           = 'Veri klasörü'
        st_dbfile            = 'Veritabanı dosyası'
        st_port              = 'RDP portu'
        st_rdp               = 'Uzak masaüstü'
        st_mode              = 'Oturum modu'
        st_watchdog          = 'Watchdog'
        st_unknown           = 'Bilinmiyor'
        st_enabled           = 'Açık'
        st_disabled          = 'Kapalı'
        st_termservice       = 'TermService: {0}'
        log_status_read     = 'Durum okundu'
        port_new             = 'Yeni RDP portu:'
        port_skip_fw         = 'Güvenlik duvarı kuralını değiştirme'
        port_apply           = 'Portu uygula'
        port_read            = 'Mevcut portu oku'
        rdp_enable           = 'Uzak masaüstünü etkinleştir'
        rdp_disable          = 'Uzak masaüstünü devre dışı bırak'
        port_confirm         = 'RDP portu {0} olarak değiştirilsin mi?'
        rdp_enable_confirm   = 'Bu makinede uzak masaüstü bağlantıları etkinleştirilsin mi?'
        rdp_disable_confirm  = 'Uzak masaüstü bağlantıları devre dışı bırakılsın mı? Mevcut oturumlar etkilenebilir.'
        log_port_set         = 'RDP portunu {0} yap'
        log_rdp_enable       = 'Uzak masaüstünü etkinleştir'
        log_rdp_disable      = 'Uzak masaüstünü devre dışı bırak'
        mode_concurrent      = 'Eşzamanlı (çoklu oturum)'
        mode_standard        = 'Standart (tek oturum)'
        mode_dryrun          = 'Analiz et (dry run)'
        mode_apply           = 'Modu uygula'
        mode_apply_confirm   = '{0} oturum modu uygulansın mı? Bu işlem termsrv.dll dosyasını değiştirir (önce snapshot alınır). Önce analiz etmeniz önerilir.'
        mode_name_concurrent = 'Eşzamanlı'
        mode_name_standard   = 'Standart'
        log_mode_dryrun      = 'Oturum modu analizi'
        log_mode_apply       = '{0} oturum modunu uygula'
        users_add            = 'Ekle'
        users_remove         = 'Seçileni kaldır'
        users_add_confirm    = '"{0}" Uzak Masaüstü Kullanıcıları grubuna eklensin mi?'
        users_remove_confirm = '"{0}" Uzak Masaüstü Kullanıcıları grubundan çıkarılsın mı?'
        log_users_list       = 'Kullanıcılar listelendi'
        log_user_add         = '{0} kullanıcısını ekle'
        log_user_remove      = '{0} kullanıcısını kaldır'
        col_identity         = 'Kimlik'
        col_name             = 'Ad'
        col_domain           = 'Etki alanı'
        col_objclass         = 'Nesne türü'
        col_sessionname      = 'Oturum adı'
        col_user             = 'Kullanıcı'
        col_sessionid        = 'Oturum ID'
        col_state            = 'Durum'
        col_id               = 'ID'
        ses_disconnect       = 'Seçileni bağlantısını kes'
        ses_logoff           = 'Seçileni oturumu kapat'
        ses_disc_confirm     = '{0} numaralı oturumun bağlantısı kesilsin mi? Oturum açık kalır ve yeniden bağlanılabilir.'
        ses_logoff_confirm   = '{0} numaralı oturum kapatılsın mı? Bu oturumdaki kaydedilmemiş işler kaybolur.'
        log_ses_list        = 'Oturumlar listelendi'
        log_ses_disc        = '{0} numaralı oturumun bağlantısını kes'
        log_ses_logoff      = '{0} numaralı oturumu kapat'
        snap_all             = 'Enforced snapshot''ları da göster'
        snap_new             = 'Yeni snapshot al'
        snap_restore         = 'Seçileni geri yükle'
        snap_remove          = 'Seçileni sil'
        snap_restore_confirm = '{0} numaralı snapshot ile termsrv.dll geri yüklensin mi? Mevcut sistem dosyasının üzerine yazılır.'
        snap_remove_confirm  = '{0} numaralı snapshot silinsin mi? Bu işlem geri alınamaz.'
        log_snap_list       = 'Snapshot''lar listelendi'
        log_snap_new        = 'Snapshot oluştur'
        log_snap_restore    = '{0} numaralı snapshot''ı geri yükle'
        log_snap_remove     = '{0} numaralı snapshot''ı sil'
        wd_status            = 'Durumu göster'
        wd_start             = 'Watchdog''u başlat'
        wd_stop              = 'Watchdog''u durdur'
        wd_run               = 'Şimdi bir döngü çalıştır'
        wd_start_confirm     = 'Watchdog zamanlanmış görevi kaydedilsin mi? (Açılışta SYSTEM hesabıyla çalışır)'
        wd_stop_confirm      = 'Watchdog zamanlanmış görevi kaldırılsın mı?'
        log_wd_status        = 'Watchdog durumu okundu'
        log_wd_start         = 'Watchdog''u başlat'
        log_wd_stop          = 'Watchdog''u durdur'
        log_wd_run           = 'Watchdog döngüsünü çalıştır'
    }
    en = @{
        app_title            = 'RDPControl'
        app_title_noadmin    = 'RDPControl (not elevated - changes will fail)'
        title_confirm        = 'Confirm'
        title_error          = 'Error'
        btn_refresh          = 'Refresh'
        last_result          = 'Last result:'
        lang_label           = 'Language:'
        log_completed        = '{0} completed.'
        log_failed           = '{0} failed: {1}'
        log_ready            = 'RDPControl GUI ready.'
        log_not_elevated     = 'This session is not elevated. Restart PowerShell as Administrator.'
        log_not_init         = 'RDPControl environment is not initialized yet. Use the Setup tab.'
        tab_setup            = 'Setup'
        tab_status           = 'Status'
        tab_port             = 'Port & Service'
        tab_mode             = 'Session Mode'
        tab_users            = 'Users'
        tab_sessions         = 'Sessions'
        tab_snapshots        = 'Snapshots'
        tab_watchdog         = 'Watchdog'
        setup_intro          = 'RDPControl needs its environment set up once before use. Check the requirements and install or repair what is missing.'
        setup_check          = 'Check'
        setup_install        = 'Install'
        setup_repair         = 'Repair missing'
        setup_snapshot       = 'Take termsrv.dll snapshot after install'
        setup_install_confirm = 'Install the RDPControl environment? (creates the %ProgramData%\RDPControl folder and database)'
        setup_repair_confirm = 'Repair missing components? Existing data is kept.'
        setup_state_ready    = 'Status: environment is ready.'
        setup_state_not_ready = 'Status: environment is not set up. Click "Install" to continue.'
        setup_need_admin     = 'Setup must be run as Administrator.'
        col_item             = 'Item'
        col_result           = 'Result'
        chk_admin            = 'Administrator rights'
        chk_ps               = 'PowerShell version'
        chk_module           = 'RDPControl module'
        chk_lib              = 'SQLite library'
        chk_env              = 'Environment configuration (environment.json)'
        chk_db               = 'Database (rdpcontrol.db)'
        res_ok               = 'OK'
        res_missing          = 'Missing'
        log_setup_install    = 'Environment install'
        log_setup_repair     = 'Environment repair'
        log_setup_snapshot   = 'Post-install snapshot'
        st_setting           = 'Setting'
        st_value             = 'Value'
        st_env               = 'Environment'
        st_env_missing       = 'Not installed'
        st_datadir           = 'Data folder'
        st_dbfile            = 'Database file'
        st_port              = 'RDP port'
        st_rdp               = 'Remote Desktop'
        st_mode              = 'Session mode'
        st_watchdog          = 'Watchdog'
        st_unknown           = 'Unknown'
        st_enabled           = 'Enabled'
        st_disabled          = 'Disabled'
        st_termservice       = 'TermService: {0}'
        log_status_read      = 'Status read'
        port_new             = 'New RDP port:'
        port_skip_fw         = 'Do not change firewall rule'
        port_apply           = 'Apply port'
        port_read            = 'Read current port'
        rdp_enable           = 'Enable Remote Desktop'
        rdp_disable          = 'Disable Remote Desktop'
        port_confirm         = 'Change the RDP port to {0}?'
        rdp_enable_confirm   = 'Enable Remote Desktop connections on this machine?'
        rdp_disable_confirm  = 'Disable Remote Desktop connections? Existing sessions may be affected.'
        log_port_set         = 'Set RDP port {0}'
        log_rdp_enable       = 'Enable Remote Desktop'
        log_rdp_disable      = 'Disable Remote Desktop'
        mode_concurrent      = 'Concurrent (multi-session)'
        mode_standard        = 'Standard (single-session)'
        mode_dryrun          = 'Analyze (dry run)'
        mode_apply           = 'Apply mode'
        mode_apply_confirm   = 'Apply {0} session mode? This patches termsrv.dll (a snapshot is taken first). Running an analysis first is recommended.'
        mode_name_concurrent = 'Concurrent'
        mode_name_standard   = 'Standard'
        log_mode_dryrun      = 'Session mode analysis'
        log_mode_apply       = 'Apply {0} session mode'
        users_add            = 'Add'
        users_remove         = 'Remove selected'
        users_add_confirm    = 'Add "{0}" to Remote Desktop Users?'
        users_remove_confirm = 'Remove "{0}" from Remote Desktop Users?'
        log_users_list       = 'Users listed'
        log_user_add         = 'Add user {0}'
        log_user_remove      = 'Remove user {0}'
        col_identity         = 'Identity'
        col_name             = 'Name'
        col_domain           = 'Domain'
        col_objclass         = 'Object class'
        col_sessionname      = 'Session name'
        col_user             = 'User'
        col_sessionid        = 'Session ID'
        col_state            = 'State'
        col_id               = 'ID'
        ses_disconnect       = 'Disconnect selected'
        ses_logoff           = 'Log off selected'
        ses_disc_confirm     = 'Disconnect session {0}? The session stays alive and can be reconnected.'
        ses_logoff_confirm   = 'Log off session {0}? Unsaved work in that session will be lost.'
        log_ses_list        = 'Sessions listed'
        log_ses_disc        = 'Disconnect session {0}'
        log_ses_logoff      = 'Log off session {0}'
        snap_all             = 'Include enforced snapshots'
        snap_new             = 'New snapshot'
        snap_restore         = 'Restore selected'
        snap_remove          = 'Remove selected'
        snap_restore_confirm = 'Restore termsrv.dll from snapshot {0}? This overwrites the current system binary.'
        snap_remove_confirm  = 'Delete snapshot {0}? This cannot be undone.'
        log_snap_list       = 'Snapshots listed'
        log_snap_new        = 'Create snapshot'
        log_snap_restore    = 'Restore snapshot {0}'
        log_snap_remove     = 'Remove snapshot {0}'
        wd_status            = 'Show status'
        wd_start             = 'Start watchdog'
        wd_stop              = 'Stop watchdog'
        wd_run               = 'Run cycle now'
        wd_start_confirm     = 'Register the watchdog scheduled task? (runs as SYSTEM at boot)'
        wd_stop_confirm      = 'Unregister the watchdog scheduled task?'
        log_wd_status        = 'Watchdog status read'
        log_wd_start         = 'Start watchdog'
        log_wd_stop          = 'Stop watchdog'
        log_wd_run           = 'Run watchdog cycle'
    }
}

# Turkish/English labels for DataGridView column headers, keyed by property name.
$script:HeaderKeys = @{
    Setting     = 'st_setting'
    Value       = 'st_value'
    Item        = 'col_item'
    Result      = 'col_result'
    Identity    = 'col_identity'
    Name        = 'col_name'
    Domain      = 'col_domain'
    ObjectClass = 'col_objclass'
    SessionName = 'col_sessionname'
    UserName    = 'col_user'
    SessionId   = 'col_sessionid'
    State       = 'col_state'
    Id          = 'col_id'
}

function T {
    param(
        [string]$Key,
        [object[]]$FormatArgs = @()
    )

    $table = $script:Strings[$script:Lang]
    if ($table.ContainsKey($Key)) {
        $text = [string]$table[$Key]
    } else {
        $text = [string]$script:Strings['en'][$Key]
    }
    if ([string]::IsNullOrEmpty($text)) { return $Key }
    if ($FormatArgs.Count -gt 0) { return ($text -f $FormatArgs) }
    return $text
}

function Update-GuiTexts {
    param([System.Windows.Forms.Control]$Control)

    $key = [string]$Control.Tag
    if ($key -and $script:Strings['en'].ContainsKey($key)) {
        $Control.Text = T $key
    }
    foreach ($child in $Control.Controls) {
        Update-GuiTexts -Control $child
    }
}

function Set-GuiLanguage {
    param([string]$Lang)

    $script:Lang = $Lang
    Update-GuiTexts -Control $form
    $form.Text = if ($isAdmin) { T 'app_title' } else { T 'app_title_noadmin' }
    foreach ($grid in $script:Grids) {
        Set-GridHeaders -Grid $grid
    }
    Update-SetupTab
}

#endregion

#region Helpers

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$script:Grids = @()

function Write-GuiLog {
    param([string]$Message, [string]$Level = 'INFO')

    $line = '[{0:HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level, $Message
    $script:LogBox.AppendText($line + [Environment]::NewLine)
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
}

function Show-GuiMessage {
    param(
        [string]$Text,
        [string]$Caption,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show($Text, $Caption, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Confirm-GuiAction {
    param([string]$Text)

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Text,
        (T 'title_confirm'),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

# Runs a scriptblock, logs the outcome and returns its result ($null on error).
function Invoke-GuiAction {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $result = & $Action
        Write-GuiLog -Message (T 'log_completed' @($Name))
        return $result
    } catch {
        Write-GuiLog -Message (T 'log_failed' @($Name, $_.Exception.Message)) -Level 'ERROR'
        Show-GuiMessage -Text $_.Exception.Message -Caption (T 'title_error') -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        return $null
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Test-RdpEnvironmentReady {
    # Same check as the module's Assert-RdpEnvironment guard clause.
    $envFile = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\environment.json'
    return (Test-Path -LiteralPath $envFile -PathType Leaf)
}

function ConvertTo-GuiDataTable {
    param([object[]]$Items)

    $table = New-Object -TypeName System.Data.DataTable
    if (-not $Items -or $Items.Count -eq 0) {
        return , $table
    }

    $properties = @($Items[0].PSObject.Properties.Name)
    foreach ($property in $properties) {
        [void]$table.Columns.Add($property)
    }

    foreach ($item in $Items) {
        $row = $table.NewRow()
        foreach ($property in $properties) {
            $value = $item.$property
            $row[$property] = if ($null -eq $value) { [DBNull]::Value } else { $value }
        }
        $table.Rows.Add($row)
    }

    return , $table
}

function Set-GridHeaders {
    param([System.Windows.Forms.DataGridView]$Grid)

    foreach ($column in $Grid.Columns) {
        $key = $script:HeaderKeys[[string]$column.DataPropertyName]
        if ($key) {
            $column.HeaderText = T $key
        }
    }
}

function Set-GuiGrid {
    param(
        [System.Windows.Forms.DataGridView]$Grid,
        [object[]]$Items
    )

    $Grid.DataSource = $null
    $Grid.DataSource = ConvertTo-GuiDataTable -Items $Items
    Set-GridHeaders -Grid $Grid
}

function Show-GuiOutput {
    param([object]$Value)

    $script:OutputBox.Text = ($Value | Format-List * | Out-String).Trim()
}

function Get-SelectedRowValue {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Column)

    if ($Grid.SelectedRows.Count -eq 0) {
        return $null
    }
    return $Grid.SelectedRows[0].Cells[$Column].Value
}

function New-GuiGrid {
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $script:Grids += $grid
    return $grid
}

function New-GuiButton {
    param([string]$Key)

    $button = New-Object System.Windows.Forms.Button
    $button.Tag = $Key
    $button.Text = T $Key
    $button.AutoSize = $true
    $button.Margin = New-Object System.Windows.Forms.Padding(4)
    $button.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 2)
    return $button
}

function New-GuiLabel {
    param([string]$Key)

    $label = New-Object System.Windows.Forms.Label
    $label.Tag = $Key
    $label.Text = T $Key
    $label.AutoSize = $true
    $label.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 0)
    return $label
}

function New-GuiToolbar {
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'
    $flow.AutoSize = $true
    $flow.WrapContents = $true
    $flow.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
    return $flow
}

# Stacks fixed-height toolbars above a body control that fills the rest of the tab.
function New-TabLayout {
    param(
        [System.Windows.Forms.Control[]]$Top = @(),
        [System.Windows.Forms.Control]$Body
    )

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = 'Fill'
    $table.ColumnCount = 1
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $table.RowCount = $Top.Count + 1

    for ($i = 0; $i -lt $Top.Count; $i++) {
        [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
        $table.Controls.Add($Top[$i], 0, $i)
    }

    [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $table.Controls.Add($Body, 0, $Top.Count)
    return $table
}

#endregion

#region Setup

function Get-GuiSetupStatus {
    $runtime = if ($PSVersionTable.PSEdition -eq 'Core') { 'netstandard2.0' } else { 'net46' }
    $libPath = Join-Path -Path $PSScriptRoot -ChildPath "..\lib\$runtime\System.Data.SQLite.dll"
    $dbPath = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\database\rdpcontrol.db'

    return @(
        [pscustomobject]@{ Item = T 'chk_admin';  Ok = $isAdmin; Detail = '' }
        [pscustomobject]@{ Item = T 'chk_ps';     Ok = ($PSVersionTable.PSVersion.Major -ge 5); Detail = $PSVersionTable.PSVersion.ToString() }
        [pscustomobject]@{ Item = T 'chk_module'; Ok = [bool](Get-Module -Name RDPControl); Detail = '' }
        [pscustomobject]@{ Item = T 'chk_lib';    Ok = (Test-Path -LiteralPath $libPath -PathType Leaf); Detail = '' }
        [pscustomobject]@{ Item = T 'chk_env';    Ok = (Test-RdpEnvironmentReady); Detail = '' }
        [pscustomobject]@{ Item = T 'chk_db';     Ok = (Test-Path -LiteralPath $dbPath -PathType Leaf); Detail = '' }
    )
}

function Update-SetupTab {
    if ($null -eq $script:SetupGrid) { return }

    $rows = foreach ($check in Get-GuiSetupStatus) {
        $state = if ($check.Ok) { T 'res_ok' } else { T 'res_missing' }
        $result = if ($check.Detail) { "$state ($($check.Detail))" } else { $state }
        [pscustomobject]@{ Item = $check.Item; Result = $result }
    }
    Set-GuiGrid -Grid $script:SetupGrid -Items @($rows)

    $script:SetupState.Text = if (Test-RdpEnvironmentReady) { T 'setup_state_ready' } else { T 'setup_state_not_ready' }
}

function Invoke-PostSetup {
    Update-SetupTab
    if (Test-RdpEnvironmentReady) {
        if ($script:SetupSnapshotCheck.Checked) {
            $snapshot = Invoke-GuiAction -Name (T 'log_setup_snapshot') -Action { New-RdpSnapshot -Confirm:$false }
            if ($snapshot) { Show-GuiOutput -Value $snapshot }
        }
        $tabs.SelectedTab = $tabStatus
    }
    Update-SetupTab
}

#endregion

#region Actions

function Update-StatusTab {
    $rows = @()

    if (-not (Test-RdpEnvironmentReady)) {
        $rows += [pscustomobject]@{ Setting = T 'st_env'; Value = T 'st_env_missing' }
        Set-GuiGrid -Grid $script:StatusGrid -Items $rows
        Write-GuiLog -Message (T 'log_not_init') -Level 'WARN'
        return
    }

    $environment = Invoke-GuiAction -Name (T 'log_status_read') -Action { Get-RdpEnvironment }
    if ($null -ne $environment) {
        $rows += [pscustomobject]@{ Setting = T 'st_datadir'; Value = $environment.BasePath }
        $rows += [pscustomobject]@{ Setting = T 'st_dbfile'; Value = $environment.DatabaseFile }
    }

    $port = Invoke-GuiAction -Name (T 'st_port') -Action { Get-RdpPort }
    $rows += [pscustomobject]@{ Setting = T 'st_port'; Value = if ($port) { $port.Port } else { T 'st_unknown' } }

    $service = Invoke-GuiAction -Name (T 'st_rdp') -Action { Get-RdpService }
    $rdpValue = if ($service) {
        $state = if ($service.Enabled) { T 'st_enabled' } else { T 'st_disabled' }
        '{0} ({1})' -f $state, (T 'st_termservice' @($service.Status))
    } else { T 'st_unknown' }
    $rows += [pscustomobject]@{ Setting = T 'st_rdp'; Value = $rdpValue }

    $mode = Invoke-GuiAction -Name (T 'st_mode') -Action { Get-RdpSessionMode }
    $rows += [pscustomobject]@{ Setting = T 'st_mode'; Value = if ($mode) { $mode.Mode } else { T 'st_unknown' } }

    $watchdog = Invoke-GuiAction -Name (T 'st_watchdog') -Action { Get-RdpWatchdogStatus }
    $rows += [pscustomobject]@{ Setting = T 'st_watchdog'; Value = if ($watchdog) { [string]$watchdog.State } else { T 'st_unknown' } }

    Set-GuiGrid -Grid $script:StatusGrid -Items $rows
}

function Update-UsersTab {
    $users = Invoke-GuiAction -Name (T 'log_users_list') -Action { @(Get-RdpUser) }
    Set-GuiGrid -Grid $script:UsersGrid -Items $users
}

function Update-SessionsTab {
    $sessions = Invoke-GuiAction -Name (T 'log_ses_list') -Action { @(Get-RdpSession) }
    Set-GuiGrid -Grid $script:SessionsGrid -Items $sessions
}

function Update-SnapshotsTab {
    $includeAll = $script:SnapshotAllCheck.Checked
    $snapshots = Invoke-GuiAction -Name (T 'log_snap_list') -Action {
        if ($includeAll) { @(Get-RdpSnapshot -All) } else { @(Get-RdpSnapshot) }
    }
    Set-GuiGrid -Grid $script:SnapshotsGrid -Items $snapshots
}

function Update-WatchdogTab {
    $status = Invoke-GuiAction -Name (T 'log_wd_status') -Action { Get-RdpWatchdogStatus }
    if ($status) {
        Show-GuiOutput -Value $status
    }
}

#endregion

#region Form

$form = New-Object System.Windows.Forms.Form
$form.Tag = 'app_title'
$form.Size = New-Object System.Drawing.Size(1000, 740)
$form.MinimumSize = New-Object System.Drawing.Size(860, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Log panel (bottom)
$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = 'Bottom'
$logPanel.Height = 170

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.Dock = 'Fill'
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logPanel.Controls.Add($script:LogBox)

# Header with language switch (top)
$headerPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$headerPanel.Dock = 'Top'
$headerPanel.AutoSize = $true
$headerPanel.WrapContents = $false
$headerPanel.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)

# Flow layout keeps the combo box after the label, whatever the label's width is.
$langLabel = New-GuiLabel -Key 'lang_label'

$script:LangCombo = New-Object System.Windows.Forms.ComboBox
$script:LangCombo.DropDownStyle = 'DropDownList'
$script:LangCombo.Width = 140
$script:LangCombo.Margin = New-Object System.Windows.Forms.Padding(4, 4, 4, 4)
[void]$script:LangCombo.Items.Add('Türkçe')
[void]$script:LangCombo.Items.Add('English')
$script:LangCombo.SelectedIndex = 0

$headerPanel.Controls.AddRange(@($langLabel, $script:LangCombo))

# Output panel
$script:OutputBox = New-Object System.Windows.Forms.TextBox
$script:OutputBox.Multiline = $true
$script:OutputBox.ReadOnly = $true
$script:OutputBox.ScrollBars = 'Both'
$script:OutputBox.WordWrap = $false
$script:OutputBox.Dock = 'Fill'
$script:OutputBox.Font = New-Object System.Drawing.Font('Consolas', 9)

$outputLabel = New-GuiLabel -Key 'last_result'
$outputLabel.Dock = 'Top'
$outputLabel.Margin = New-Object System.Windows.Forms.Padding(0)
$outputLabel.Padding = New-Object System.Windows.Forms.Padding(4, 2, 0, 0)

$outputPanel = New-Object System.Windows.Forms.Panel
$outputPanel.Dock = 'Fill'
$outputPanel.Controls.Add($script:OutputBox)
$outputPanel.Controls.Add($outputLabel)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'

# ---- Setup tab --------------------------------------------------------------
$tabSetup = New-Object System.Windows.Forms.TabPage
$tabSetup.Tag = 'tab_setup'
$tabSetup.Text = T 'tab_setup'

$setupIntro = New-GuiLabel -Key 'setup_intro'
$setupIntro.Margin = New-Object System.Windows.Forms.Padding(8, 10, 8, 4)
$setupIntro.MaximumSize = New-Object System.Drawing.Size(900, 0)

$script:SetupState = New-Object System.Windows.Forms.Label
$script:SetupState.AutoSize = $true
$script:SetupState.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$script:SetupState.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 4)

$setupCheck = New-GuiButton -Key 'setup_check'
$setupInstall = New-GuiButton -Key 'setup_install'
$setupRepair = New-GuiButton -Key 'setup_repair'
$script:SetupSnapshotCheck = New-Object System.Windows.Forms.CheckBox
$script:SetupSnapshotCheck.Tag = 'setup_snapshot'
$script:SetupSnapshotCheck.Text = T 'setup_snapshot'
$script:SetupSnapshotCheck.AutoSize = $true
$script:SetupSnapshotCheck.Checked = $true
$script:SetupSnapshotCheck.Margin = New-Object System.Windows.Forms.Padding(12, 10, 4, 4)

$setupTop = New-GuiToolbar
$setupTop.Controls.AddRange(@($setupCheck, $setupInstall, $setupRepair, $script:SetupSnapshotCheck))

$script:SetupGrid = New-GuiGrid

$tabSetup.Controls.Add((New-TabLayout -Top @($setupIntro, $script:SetupState, $setupTop) -Body $script:SetupGrid))

$setupCheck.Add_Click({ Update-SetupTab })

$setupInstall.Add_Click({
    if (-not $isAdmin) { Show-GuiMessage -Text (T 'setup_need_admin') -Caption (T 'title_error') -Icon ([System.Windows.Forms.MessageBoxIcon]::Error); return }
    if (-not (Confirm-GuiAction -Text (T 'setup_install_confirm'))) { return }
    $result = Invoke-GuiAction -Name (T 'log_setup_install') -Action { Initialize-RdpEnvironment -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Invoke-PostSetup
})

$setupRepair.Add_Click({
    if (-not $isAdmin) { Show-GuiMessage -Text (T 'setup_need_admin') -Caption (T 'title_error') -Icon ([System.Windows.Forms.MessageBoxIcon]::Error); return }
    if (-not (Confirm-GuiAction -Text (T 'setup_repair_confirm'))) { return }
    $result = Invoke-GuiAction -Name (T 'log_setup_repair') -Action { Initialize-RdpEnvironment -Force -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Invoke-PostSetup
})

# ---- Status tab -------------------------------------------------------------
$tabStatus = New-Object System.Windows.Forms.TabPage
$tabStatus.Tag = 'tab_status'
$tabStatus.Text = T 'tab_status'

$script:StatusGrid = New-GuiGrid
$statusRefresh = New-GuiButton -Key 'btn_refresh'
$statusRefresh.Add_Click({ Update-StatusTab })

$statusTop = New-GuiToolbar
$statusTop.Controls.Add($statusRefresh)
$tabStatus.Controls.Add((New-TabLayout -Top @($statusTop) -Body $script:StatusGrid))

# ---- Port & Service tab -----------------------------------------------------
$tabPort = New-Object System.Windows.Forms.TabPage
$tabPort.Tag = 'tab_port'
$tabPort.Text = T 'tab_port'

$portLabel = New-GuiLabel -Key 'port_new'
$script:PortNumeric = New-Object System.Windows.Forms.NumericUpDown
$script:PortNumeric.Minimum = 1
$script:PortNumeric.Maximum = 65535
$script:PortNumeric.Value = 3389
$script:PortNumeric.Width = 90
$script:PortNumeric.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 4)

$script:SkipFirewallCheck = New-Object System.Windows.Forms.CheckBox
$script:SkipFirewallCheck.Tag = 'port_skip_fw'
$script:SkipFirewallCheck.Text = T 'port_skip_fw'
$script:SkipFirewallCheck.AutoSize = $true
$script:SkipFirewallCheck.Margin = New-Object System.Windows.Forms.Padding(12, 9, 4, 4)

$portApply = New-GuiButton -Key 'port_apply'
$portRead = New-GuiButton -Key 'port_read'
$rdpEnable = New-GuiButton -Key 'rdp_enable'
$rdpDisable = New-GuiButton -Key 'rdp_disable'

$portRow = New-GuiToolbar
$portRow.Controls.AddRange(@($portLabel, $script:PortNumeric, $script:SkipFirewallCheck, $portApply, $portRead))
$rdpRow = New-GuiToolbar
$rdpRow.Controls.AddRange(@($rdpEnable, $rdpDisable))

$portApply.Add_Click({
    $port = [int]$script:PortNumeric.Value
    $skip = $script:SkipFirewallCheck.Checked
    if (-not (Confirm-GuiAction -Text (T 'port_confirm' @($port)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_port_set' @($port)) -Action {
        Set-RdpPort -Port $port -SkipFirewall:$skip -Force -Confirm:$false
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-StatusTab
})

$portRead.Add_Click({
    $port = Invoke-GuiAction -Name (T 'st_port') -Action { Get-RdpPort }
    if ($port) {
        $script:PortNumeric.Value = [decimal]$port.Port
        Show-GuiOutput -Value $port
    }
})

$rdpEnable.Add_Click({
    if (-not (Confirm-GuiAction -Text (T 'rdp_enable_confirm'))) { return }
    $result = Invoke-GuiAction -Name (T 'log_rdp_enable') -Action { Set-RdpService -Enabled -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Update-StatusTab
})

$rdpDisable.Add_Click({
    if (-not (Confirm-GuiAction -Text (T 'rdp_disable_confirm'))) { return }
    $result = Invoke-GuiAction -Name (T 'log_rdp_disable') -Action { Set-RdpService -Disabled -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Update-StatusTab
})

$tabPort.Controls.Add((New-TabLayout -Top @($portRow, $rdpRow) -Body (New-Object System.Windows.Forms.Panel)))

# ---- Session Mode tab -------------------------------------------------------
$tabMode = New-Object System.Windows.Forms.TabPage
$tabMode.Tag = 'tab_mode'
$tabMode.Text = T 'tab_mode'

$script:ModeConcurrent = New-Object System.Windows.Forms.RadioButton
$script:ModeConcurrent.Tag = 'mode_concurrent'
$script:ModeConcurrent.Text = T 'mode_concurrent'
$script:ModeConcurrent.Checked = $true
$script:ModeConcurrent.AutoSize = $true
$script:ModeConcurrent.Margin = New-Object System.Windows.Forms.Padding(4, 8, 24, 4)

$script:ModeStandard = New-Object System.Windows.Forms.RadioButton
$script:ModeStandard.Tag = 'mode_standard'
$script:ModeStandard.Text = T 'mode_standard'
$script:ModeStandard.AutoSize = $true
$script:ModeStandard.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 4)

$modeDryRun = New-GuiButton -Key 'mode_dryrun'
$modeApply = New-GuiButton -Key 'mode_apply'

$modeRadioRow = New-GuiToolbar
$modeRadioRow.Controls.AddRange(@($script:ModeConcurrent, $script:ModeStandard))
$modeActionRow = New-GuiToolbar
$modeActionRow.Controls.AddRange(@($modeDryRun, $modeApply))

$modeDryRun.Add_Click({
    $enable = $script:ModeConcurrent.Checked
    $result = Invoke-GuiAction -Name (T 'log_mode_dryrun') -Action {
        if ($enable) { Set-RdpSessionMode -Enabled -DryRun } else { Set-RdpSessionMode -Disabled -DryRun }
    }
    if ($result) { Show-GuiOutput -Value $result }
})

$modeApply.Add_Click({
    $enable = $script:ModeConcurrent.Checked
    $targetName = if ($enable) { T 'mode_name_concurrent' } else { T 'mode_name_standard' }
    if (-not (Confirm-GuiAction -Text (T 'mode_apply_confirm' @($targetName)))) { return }

    $result = Invoke-GuiAction -Name (T 'log_mode_apply' @($targetName)) -Action {
        if ($enable) { Set-RdpSessionMode -Enabled -Force -Confirm:$false } else { Set-RdpSessionMode -Disabled -Force -Confirm:$false }
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-StatusTab
})

$tabMode.Controls.Add((New-TabLayout -Top @($modeRadioRow, $modeActionRow) -Body (New-Object System.Windows.Forms.Panel)))

# ---- Users tab --------------------------------------------------------------
$tabUsers = New-Object System.Windows.Forms.TabPage
$tabUsers.Tag = 'tab_users'
$tabUsers.Text = T 'tab_users'

$script:UsersGrid = New-GuiGrid
$usersIdentity = New-Object System.Windows.Forms.TextBox
$usersIdentity.Width = 260
$usersIdentity.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 4)
$usersAdd = New-GuiButton -Key 'users_add'
$usersRemove = New-GuiButton -Key 'users_remove'
$usersRefresh = New-GuiButton -Key 'btn_refresh'

$usersTop = New-GuiToolbar
$usersTop.Controls.AddRange(@($usersIdentity, $usersAdd, $usersRemove, $usersRefresh))
$tabUsers.Controls.Add((New-TabLayout -Top @($usersTop) -Body $script:UsersGrid))

$usersAdd.Add_Click({
    $identity = $usersIdentity.Text.Trim()
    if (-not $identity) { return }
    if (-not (Confirm-GuiAction -Text (T 'users_add_confirm' @($identity)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_user_add' @($identity)) -Action {
        Add-RdpUser -Identity $identity -Confirm:$false
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-UsersTab
})

$usersRemove.Add_Click({
    $identity = Get-SelectedRowValue -Grid $script:UsersGrid -Column 'Identity'
    if (-not $identity) { return }
    if (-not (Confirm-GuiAction -Text (T 'users_remove_confirm' @($identity)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_user_remove' @($identity)) -Action {
        Remove-RdpUser -Identity ([string]$identity) -Force -Confirm:$false
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-UsersTab
})

$usersRefresh.Add_Click({ Update-UsersTab })

# ---- Sessions tab ----------------------------------------------------------
$tabSessions = New-Object System.Windows.Forms.TabPage
$tabSessions.Tag = 'tab_sessions'
$tabSessions.Text = T 'tab_sessions'

$script:SessionsGrid = New-GuiGrid
$sessionsRefresh = New-GuiButton -Key 'btn_refresh'
$sessionsDisconnect = New-GuiButton -Key 'ses_disconnect'
$sessionsLogoff = New-GuiButton -Key 'ses_logoff'

$sessionsTop = New-GuiToolbar
$sessionsTop.Controls.AddRange(@($sessionsRefresh, $sessionsDisconnect, $sessionsLogoff))
$tabSessions.Controls.Add((New-TabLayout -Top @($sessionsTop) -Body $script:SessionsGrid))

$sessionsRefresh.Add_Click({ Update-SessionsTab })

$sessionsDisconnect.Add_Click({
    $sessionId = Get-SelectedRowValue -Grid $script:SessionsGrid -Column 'SessionId'
    if ($null -eq $sessionId) { return }
    $id = [int]$sessionId
    if (-not (Confirm-GuiAction -Text (T 'ses_disc_confirm' @($id)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_ses_disc' @($id)) -Action {
        Disconnect-RdpSession -SessionId $id -Force -Confirm:$false
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-SessionsTab
})

$sessionsLogoff.Add_Click({
    $sessionId = Get-SelectedRowValue -Grid $script:SessionsGrid -Column 'SessionId'
    if ($null -eq $sessionId) { return }
    $id = [int]$sessionId
    if (-not (Confirm-GuiAction -Text (T 'ses_logoff_confirm' @($id)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_ses_logoff' @($id)) -Action {
        Stop-RdpSession -SessionId $id -Force -Confirm:$false
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-SessionsTab
})

# ---- Snapshots tab ----------------------------------------------------------
$tabSnapshots = New-Object System.Windows.Forms.TabPage
$tabSnapshots.Tag = 'tab_snapshots'
$tabSnapshots.Text = T 'tab_snapshots'

$script:SnapshotsGrid = New-GuiGrid
$script:SnapshotAllCheck = New-Object System.Windows.Forms.CheckBox
$script:SnapshotAllCheck.Tag = 'snap_all'
$script:SnapshotAllCheck.Text = T 'snap_all'
$script:SnapshotAllCheck.AutoSize = $true
$script:SnapshotAllCheck.Margin = New-Object System.Windows.Forms.Padding(4, 9, 12, 4)

$snapshotsRefresh = New-GuiButton -Key 'btn_refresh'
$snapshotsNew = New-GuiButton -Key 'snap_new'
$snapshotsRestore = New-GuiButton -Key 'snap_restore'
$snapshotsRemove = New-GuiButton -Key 'snap_remove'

$snapshotsTop = New-GuiToolbar
$snapshotsTop.Controls.AddRange(@($script:SnapshotAllCheck, $snapshotsRefresh, $snapshotsNew, $snapshotsRestore, $snapshotsRemove))
$tabSnapshots.Controls.Add((New-TabLayout -Top @($snapshotsTop) -Body $script:SnapshotsGrid))

$snapshotsRefresh.Add_Click({ Update-SnapshotsTab })
$script:SnapshotAllCheck.Add_CheckedChanged({ Update-SnapshotsTab })

$snapshotsNew.Add_Click({
    $result = Invoke-GuiAction -Name (T 'log_snap_new') -Action { New-RdpSnapshot -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Update-SnapshotsTab
})

$snapshotsRestore.Add_Click({
    $snapshotId = Get-SelectedRowValue -Grid $script:SnapshotsGrid -Column 'Id'
    if ($null -eq $snapshotId) { return }
    $id = [long]$snapshotId
    if (-not (Confirm-GuiAction -Text (T 'snap_restore_confirm' @($id)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_snap_restore' @($id)) -Action {
        Restore-RdpSnapshot -Id $id -Force
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-StatusTab
})

$snapshotsRemove.Add_Click({
    $snapshotId = Get-SelectedRowValue -Grid $script:SnapshotsGrid -Column 'Id'
    if ($null -eq $snapshotId) { return }
    $id = [int]$snapshotId
    if (-not (Confirm-GuiAction -Text (T 'snap_remove_confirm' @($id)))) { return }
    $result = Invoke-GuiAction -Name (T 'log_snap_remove' @($id)) -Action {
        Remove-RdpSnapshot -Id $id -Force -Confirm:$false
    }
    if ($result) { Show-GuiOutput -Value $result }
    Update-SnapshotsTab
})

# ---- Watchdog tab -----------------------------------------------------------
$tabWatchdog = New-Object System.Windows.Forms.TabPage
$tabWatchdog.Tag = 'tab_watchdog'
$tabWatchdog.Text = T 'tab_watchdog'

$watchStatus = New-GuiButton -Key 'wd_status'
$watchStart = New-GuiButton -Key 'wd_start'
$watchStop = New-GuiButton -Key 'wd_stop'
$watchRun = New-GuiButton -Key 'wd_run'

$watchTop = New-GuiToolbar
$watchTop.Controls.AddRange(@($watchStatus, $watchStart, $watchStop, $watchRun))
$tabWatchdog.Controls.Add((New-TabLayout -Top @($watchTop) -Body (New-Object System.Windows.Forms.Panel)))

$watchStatus.Add_Click({ Update-WatchdogTab })

$watchStart.Add_Click({
    if (-not (Confirm-GuiAction -Text (T 'wd_start_confirm'))) { return }
    $result = Invoke-GuiAction -Name (T 'log_wd_start') -Action { Start-RdpWatchdog -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Update-WatchdogTab
})

$watchStop.Add_Click({
    if (-not (Confirm-GuiAction -Text (T 'wd_stop_confirm'))) { return }
    $result = Invoke-GuiAction -Name (T 'log_wd_stop') -Action { Stop-RdpWatchdog -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Update-WatchdogTab
})

$watchRun.Add_Click({
    $result = Invoke-GuiAction -Name (T 'log_wd_run') -Action { Invoke-RdpWatchdog -Confirm:$false }
    if ($result) { Show-GuiOutput -Value $result }
    Update-StatusTab
})

# ---- Assemble ---------------------------------------------------------------
$tabs.TabPages.AddRange(@($tabSetup, $tabStatus, $tabPort, $tabMode, $tabUsers, $tabSessions, $tabSnapshots, $tabWatchdog))

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Horizontal'
$split.SplitterDistance = 400
$split.Panel1.Controls.Add($tabs)
$split.Panel2.Controls.Add($outputPanel)

# Fill control first, then docked edges (WinForms docking order).
$form.Controls.Add($split)
$form.Controls.Add($logPanel)
$form.Controls.Add($headerPanel)

$script:LangCombo.Add_SelectedIndexChanged({
    Set-GuiLanguage -Lang $(if ($script:LangCombo.SelectedIndex -eq 0) { 'tr' } else { 'en' })
})

$tabs.Add_SelectedIndexChanged({
    if (-not (Test-RdpEnvironmentReady)) { return }
    switch ($tabs.SelectedTab) {
        $tabStatus    { Update-StatusTab }
        $tabUsers     { Update-UsersTab }
        $tabSessions  { Update-SessionsTab }
        $tabSnapshots { Update-SnapshotsTab }
        $tabWatchdog  { Update-WatchdogTab }
    }
})

$form.Add_Shown({
    if (-not $isAdmin) {
        Write-GuiLog -Message (T 'log_not_elevated') -Level 'WARN'
    }
    Update-SetupTab
    if (Test-RdpEnvironmentReady) {
        $tabs.SelectedTab = $tabStatus
        Update-StatusTab
    } else {
        Write-GuiLog -Message (T 'log_not_init') -Level 'WARN'
    }
    Write-GuiLog -Message (T 'log_ready')
})

if (-not $isAdmin) {
    $form.Text = T 'app_title_noadmin'
}

[void]$form.ShowDialog()
$form.Dispose()

#endregion
