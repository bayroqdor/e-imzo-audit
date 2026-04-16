# =====================================================================
# E-IMZO Monitoring tizimini to'liq avtomatik o'rnatish skripti
# =====================================================================

$botToken = "SIZNING_BOT_TOKENINGIZ"
$chatId = "SIZNING_CHAT_ID"

$installDir = "C:\DSAUDIT"
$targetDir = "C:\DSKEYS"
$serviceName = "EIMZOMonitor"

Write-Host "1. Papkalar tayyorlanmoqda..." -ForegroundColor Cyan
if (-not (Test-Path $installDir)) { New-Item -Path $installDir -ItemType Directory | Out-Null }
if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory | Out-Null }

Write-Host "2. Windows File System Auditi yoqilmoqda (auditpol)..." -ForegroundColor Cyan
auditpol /set /subcategory:"File System" /success:enable /failure:enable | Out-Null

Write-Host "3. E-IMZO papkasiga kuzatuv qoidasi (SACL) o'rnatilmoqda..." -ForegroundColor Cyan
$acl = Get-Acl $targetDir
$auditUser = "Everyone"
$auditRules = "ReadAndExecute, Modify, Delete"
$inherit = "ContainerInherit, ObjectInherit"
$propagate = "None"
$auditType = "Success"
$rule = New-Object System.Security.AccessControl.FileSystemAuditRule($auditUser, $auditRules, $inherit, $propagate, $auditType)
$acl.SetAuditRule($rule)
$acl | Set-Acl $targetDir

Write-Host "4. Asosiy monitoring skripti yaratilmoqda..." -ForegroundColor Cyan
# Skript matni (Single-quote Here-String ishlatilgan, o'zgaruvchilar buzilmaydi)
$scriptContent = @"
# Telegram sozlamalari
`$botToken = `"$botToken`"
`$chatId = `"$chatId`"

# Qaysi papkani qidirish kerakligi
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
        if ((`$now - `$eventCache[`$key]).TotalSeconds -gt `$cacheTimeoutSeconds) {
            `$keysToRemove += `$key
        }
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
                    Write-Log "HARAKAT: User: `$subjectUserName | Fayl: `$objectName | Process: `$processName (`$actionType)"

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
                        Write-Log "SUCCESS: Telegramga xabar yuborildi."
                    } catch {
                        Write-Log "XATOLIK (Telegram): Yuborib bolmadi. Sabab: `$(`$_.Exception.Message)"
                    }
                }
            }
        }
    }
    `$lastCheck = `$now
}
"@

$scriptContent | Out-File -FilePath "$installDir\DSAUDIT.ps1" -Encoding UTF8

Write-Host "5. NSSM yuklab olinmoqda va o'rnatilmoqda..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$nssmZip = "$installDir\nssm.zip"
$nssmExtracted = "$installDir\nssm_temp"

# Eski xizmat bo'lsa to'xtatib o'chirish (yangilash uchun)
if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
    Stop-Service $serviceName -Force
    cmd.exe /c "$installDir\nssm.exe remove $serviceName confirm" | Out-Null
    Start-Sleep -Seconds 2
}

if (-not (Test-Path "$installDir\nssm.exe")) {
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $nssmZip
    Expand-Archive -Path $nssmZip -DestinationPath $nssmExtracted -Force
    Copy-Item "$nssmExtracted\nssm-2.24\win64\nssm.exe" -Destination "$installDir\nssm.exe" -Force
    Remove-Item $nssmZip -Force
    Remove-Item $nssmExtracted -Recurse -Force
}

Write-Host "6. Windows Service (NSSM) yaratilmoqda va ishga tushirilmoqda..." -ForegroundColor Cyan
$psPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$psArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$installDir\DSAUDIT.ps1`""

# CMD orqali NSSM ni orqa fonda sozlash
cmd.exe /c "$installDir\nssm.exe install $serviceName `"$psPath`" $psArgs" | Out-Null
cmd.exe /c "$installDir\nssm.exe set $serviceName AppDirectory `"$installDir`"" | Out-Null
cmd.exe /c "$installDir\nssm.exe start $serviceName" | Out-Null

Write-Host "=====================================================" -ForegroundColor Green
Write-Host "MUVAFFAQIYATLI YAKUNLANDI!" -ForegroundColor Green
Write-Host "Barcha sozlamalar bajarildi va '$serviceName' xizmati ishga tushdi." -ForegroundColor Green
Write-Host "Loglar manzili: $installDir\DSAUDIT_log.txt" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Green
