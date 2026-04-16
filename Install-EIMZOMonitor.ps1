# =====================================================================
# E-IMZO Monitoring tizimini to'liq avtomatik o'rnatish skripti (V3 - Fix Spaces)
# =====================================================================

$botToken = "SIZNING_BOT_TOKENINGIZ"
$chatId = "SIZNING_CHAT_ID"

# Siz belgilagan papkalar:
$installDir = "C:\Program Files\DSservice"
$targetDir = "C:\DSKEYS"
$serviceName = "EIMZOMonitor"

Write-Host "1. Papkalar tayyorlanmoqda..." -ForegroundColor Cyan
if (-not (Test-Path $installDir)) { New-Item -Path $installDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }

Write-Host "2. Windows File System Auditi yoqilmoqda (auditpol)..." -ForegroundColor Cyan
& auditpol /set /subcategory:"Файловая система" /success:enable /failure:enable *>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    & auditpol /set /subcategory:"File System" /success:enable /failure:enable *>&1 | Out-Null
}

Write-Host "3. E-IMZO papkasiga kuzatuv qoidasi (SACL) o'rnatilmoqda..." -ForegroundColor Cyan
$sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0")
$auditUser = $sid.Translate([System.Security.Principal.NTAccount]).Value

$acl = Get-Acl $targetDir
$auditRules = "ReadAndExecute, Modify, Delete"
$inherit = "ContainerInherit, ObjectInherit"
$propagate = "None"
$auditType = "Success"
$rule = New-Object System.Security.AccessControl.FileSystemAuditRule($auditUser, $auditRules, $inherit, $propagate, $auditType)
$acl.SetAuditRule($rule)
$acl | Set-Acl $targetDir

Write-Host "4. Asosiy monitoring skripti yaratilmoqda..." -ForegroundColor Cyan
$scriptContent = @"
`$botToken = `"$botToken`"
`$chatId = `"$chatId`"
`$targetFolderName = `"DSKEYS`" 
`$logFile = `"$installDir\DSAUDIT_log.txt`"
`$eventCache = @{}
`$cacheTimeoutSeconds = 30

function Write-Log {
    param([string]`$Message)
    `$time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "`$time - `$Message" | Out-File -FilePath `$logFile -Append -Encoding UTF8
}

Write-Log "=== E-IMZO Monitoring ishga tushdi (Anti-Spam) ==="
`$lastCheck = Get-Date

while (`$true) {
    Start-Sleep -Seconds 5
    `$now = Get-Date
    `$keysToRemove = @()
    foreach (`$key in `$eventCache.Keys) {
        if ((`$now - `$eventCache[`$key]).TotalSeconds -gt `$cacheTimeoutSeconds) { `$keysToRemove += `$key }
    }
    foreach (`$key in `$keysToRemove) { `$eventCache.Remove(`$key) }

    `$events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4663; StartTime=`$lastCheck; EndTime=`$now} -ErrorAction SilentlyContinue

    if (`$events) {
        foreach (`$event in `$events) {
            `$xml = [xml]`$event.ToXml()
            `$eventData = `$xml.Event.EventData.Data
            
            `$objectName = (`$eventData | Where-Object { `$_.Name -eq 'ObjectName' }).'#text'
            `$processName = (`$eventData | Where-Object { `$_.Name -eq 'ProcessName' }).'#text'
            `$subjectUserName = (`$eventData | Where-Object { `$_.Name -eq 'SubjectUserName' }).'#text'

            if (`$objectName -match "\.pfx`$" -and `$objectName -match `$targetFolderName -and `$subjectUserName -notmatch "\`$`$") {
                `$actionType = if (`$processName -match "explorer.exe") { "Nusxalash yoki Korish" } else { "Dastur orqali murojaat" }
                `$fileNameOnly = Split-Path `$objectName -Leaf
                `$eventHash = "`$subjectUserName|`$fileNameOnly|`$actionType"
                
                if (-not `$eventCache.ContainsKey(`$eventHash)) {
                    `$eventCache[`$eventHash] = `$now
                    Write-Log "HARAKAT: `$subjectUserName | `$objectName | `$actionType"

                    `$message = "<b>!!! E-IMZO Kalitiga murojaat!</b>`n`n"
                    `$message += "<b>Xodim:</b> `$subjectUserName`n"
                    `$message += "<b>Kalit:</b> `$fileNameOnly`n"
                    `$message += "<b>Toliq yol:</b> `$objectName`n"
                    `$message += "<b>Jarayon:</b> `$processName (`$actionType)`n"
                    `$message += "<b>Vaqt:</b> `$(`$event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"

                    `$telegramUrl = "https://api.telegram.org/bot`$botToken/sendMessage"
                    `$payload = @{ chat_id = `$chatId; text = `$message; parse_mode = "HTML" } | ConvertTo-Json

                    try {
                        Invoke-RestMethod -Uri `$telegramUrl -Method Post -ContentType "application/json; charset=utf-8" -Body `$payload -ErrorAction Stop | Out-Null
                    } catch {}
                }
            }
        }
    }
    `$lastCheck = `$now
}
"@

$scriptContent | Out-File -FilePath "$installDir\DSAUDIT.ps1" -Encoding UTF8

Write-Host "5. NSSM xizmati tayyorlanmoqda..." -ForegroundColor Cyan

# Eski xizmat bo'lsa o'chirish (Start-Process orqali xavfsiz o'chirish)
if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
    Stop-Service $serviceName -Force
    Start-Process -FilePath "$installDir\nssm.exe" -ArgumentList "remove $serviceName confirm" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# nssm.exe ni nusxalash
if (-not (Test-Path "$installDir\nssm.exe")) {
    if (Test-Path "C:\DS\nssm.exe") {
        Copy-Item "C:\DS\nssm.exe" -Destination "$installDir\nssm.exe" -Force
    } else {
        Write-Warning "Diqqat: C:\DS\nssm.exe topilmadi!"
        exit
    }
}

Write-Host "6. Windows Service (NSSM) yaratilmoqda va ishga tushirilmoqda..." -ForegroundColor Cyan
$psPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$psArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$installDir\DSAUDIT.ps1`""

# Probeli bor yo'llar uchun PowerShell Start-Process orqali NSSM ni ishga tushirish:
Start-Process -FilePath "$installDir\nssm.exe" -ArgumentList "install $serviceName `"$psPath`" $psArgs" -Wait -WindowStyle Hidden
Start-Process -FilePath "$installDir\nssm.exe" -ArgumentList "set $serviceName AppDirectory `"$installDir`"" -Wait -WindowStyle Hidden
Start-Process -FilePath "$installDir\nssm.exe" -ArgumentList "start $serviceName" -Wait -WindowStyle Hidden

Write-Host "=====================================================" -ForegroundColor Green
Write-Host "MUVAFFAQIYATLI YAKUNLANDI!" -ForegroundColor Green
Write-Host "Xizmat nomi: $serviceName" -ForegroundColor Green
Write-Host "Loglar manzili: $installDir\DSAUDIT_log.txt" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Green
