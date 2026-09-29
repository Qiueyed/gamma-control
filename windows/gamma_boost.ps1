# ============================================================
# Gamma Control for Windows (port of the macOS gamma_boost)
# Run: double-click gamma_boost.bat
#      or: powershell -NoProfile -ExecutionPolicy Bypass -File gamma_boost.ps1
#
# Type a number (0-1): lower = brighter shadows (0.45 is a good boost)
# d = default boost (0.45)
# r = reset to normal (gamma 1.0)
# q = quit (restores normal gamma first)
#
# NOTE: If extreme values fail silently, Windows is blocking large gamma
# changes. One-time admin fix (run in an elevated prompt):
#   reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM" /v GdiIcmGammaRange /t REG_DWORD /d 0 /f
# ============================================================

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class GammaAPI {
    [StructLayout(LayoutKind.Sequential)]
    public struct RAMP {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] red;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] green;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] blue;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern bool SetDeviceGammaRamp(IntPtr hDC, ref RAMP lpRamp);
}
"@

$script:hdc = [GammaAPI]::GetDC([IntPtr]::Zero)

function New-Ramp {
    param([double]$Gamma = 1.0)
    $ramp = New-Object GammaAPI+RAMP
    $ramp.red   = New-Object 'ushort[]' 256
    $ramp.green = New-Object 'ushort[]' 256
    $ramp.blue  = New-Object 'ushort[]' 256
    for ($i = 0; $i -lt 256; $i++) {
        $v = [Math]::Pow($i / 255.0, $Gamma)
        if ($v -lt 0.0) { $v = 0.0 } elseif ($v -gt 1.0) { $v = 1.0 }
        $w = [ushort][Math]::Round($v * 65535.0)
        $ramp.red[$i]   = $w
        $ramp.green[$i] = $w
        $ramp.blue[$i]  = $w
    }
    return $ramp
}

function Apply-Gamma {
    param([double]$Gamma)
    $ramp = New-Ramp -Gamma $Gamma
    [void][GammaAPI]::SetDeviceGammaRamp($script:hdc, [ref]$ramp)
}

function Reset-Gamma { Apply-Gamma -Gamma 1.0 }

# Restore normal gamma on Ctrl+C or normal exit
Register-EngineEvent PowerShell.Exiting -Action { Reset-Gamma } | Out-Null

$script:current = 0.45
Apply-Gamma -Gamma $script:current
Write-Host "Gamma $script:current. Type a number (0-1), d=default(0.45), r=reset, q=quit"

while ($true) {
    Write-Host "> " -NoNewline
    $line = (Read-Host).Trim().ToLower()
    if ($line -eq "q") { break }
    if ($line -eq "r" -or $line -eq "reset") { Reset-Gamma; $script:current = 1.0; Write-Host "1.00"; continue }
    if ($line -eq "d" -or $line -eq "default") { Apply-Gamma -Gamma 0.45; $script:current = 0.45; Write-Host "0.45"; continue }
    $val = 0.0
    if ([double]::TryParse($line, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.NumberStyles]::Float, [ref]$val) -and $val -ge 0) {
        Apply-Gamma -Gamma $val
        $script:current = $val
        Write-Host ("{0:N2}" -f $val)
        continue
    }
    Write-Host "?"
}

Reset-Gamma
[void][GammaAPI]::ReleaseDC([IntPtr]::Zero, $script:hdc)
Write-Host "Restored"
