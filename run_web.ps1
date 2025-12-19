# Aurora Viking Staff - Web Runner (PowerShell)
# This script reads API keys from .env and injects them into web/index.html

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "========================================"
Write-Host "  Aurora Viking Staff - Web Runner"
Write-Host "========================================"
Write-Host ""

# Check if .env exists
if (-not (Test-Path '.env')) {
    Write-Host "[ERROR] .env file not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please create a .env file with:"
    Write-Host "  GOOGLE_MAPS_API_KEY=your_key_here"
    Write-Host "  FIREBASE_WEB_API_KEY=your_key_here"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Read .env file
$envContent = Get-Content '.env' -Raw

# Extract keys using regex
$mapsKey = ''
$firebaseKey = ''

if ($envContent -match 'GOOGLE_MAPS_API_KEY\s*=\s*([^\r\n]+)') {
    $mapsKey = $matches[1].Trim() -replace '^["'']|["'']$', ''
}

if ($envContent -match 'FIREBASE_WEB_API_KEY\s*=\s*([^\r\n]+)') {
    $firebaseKey = $matches[1].Trim() -replace '^["'']|["'']$', ''
}

Write-Host "Checking API keys..."
Write-Host ""

if ($mapsKey) {
    Write-Host "[OK] Maps key: ****$($mapsKey.Substring($mapsKey.Length - 4))" -ForegroundColor Green
} else {
    Write-Host "[WARN] GOOGLE_MAPS_API_KEY not found" -ForegroundColor Yellow
}

if ($firebaseKey) {
    Write-Host "[OK] Firebase key: ****$($firebaseKey.Substring($firebaseKey.Length - 4))" -ForegroundColor Green
} else {
    Write-Host "[WARN] FIREBASE_WEB_API_KEY not found" -ForegroundColor Yellow
}

Write-Host ""

# Check if index.html exists
if (-not (Test-Path 'web\index.html')) {
    Write-Host "[ERROR] web\index.html not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Backup original
Copy-Item 'web\index.html' 'web\index.html.backup' -Force | Out-Null
Write-Host "[OK] Backup created"

# Read index.html
$htmlContent = Get-Content 'web\index.html' -Raw

Write-Host "Injecting API keys..."

# Replace placeholders
if ($mapsKey) {
    $beforeReplace = $htmlContent -match 'MAPS_API_KEY_PLACEHOLDER'
    $htmlContent = $htmlContent -replace 'MAPS_API_KEY_PLACEHOLDER', $mapsKey
    $afterReplace = $htmlContent -match 'MAPS_API_KEY_PLACEHOLDER'
    
    if ($beforeReplace -and -not $afterReplace) {
        Write-Host "[OK] Maps key injected" -ForegroundColor Green
        # Show the replaced line for verification
        $scriptLine = $htmlContent -split "`n" | Where-Object { $_ -match 'maps.googleapis.com' }
        Write-Host "[DEBUG] Script tag: $($scriptLine.Trim())" -ForegroundColor Cyan
    } else {
        Write-Host "[ERROR] Replacement didn't work!" -ForegroundColor Red
        Write-Host "Before: $beforeReplace, After: $afterReplace" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARN] No Maps key to inject" -ForegroundColor Yellow
}

if ($firebaseKey) {
    $htmlContent = $htmlContent -replace 'FIREBASE_API_KEY_PLACEHOLDER', $firebaseKey
    Write-Host "[OK] Firebase key injected" -ForegroundColor Green
}

# Write back to file
Set-Content 'web\index.html' -Value $htmlContent -NoNewline

# Verify replacement by reading the file back
$verifyContent = Get-Content 'web\index.html' -Raw
if ($verifyContent -match 'MAPS_API_KEY_PLACEHOLDER') {
    Write-Host ""
    Write-Host "[ERROR] Replacement failed! Placeholder still found." -ForegroundColor Red
    Write-Host "Maps key was: $mapsKey" -ForegroundColor Yellow
    Write-Host "Checking file content..." -ForegroundColor Yellow
    $line = Get-Content 'web\index.html' | Select-String "MAPS_API_KEY"
    Write-Host "Found line: $line" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Double-check by looking at the actual script tag
$scriptLine = Get-Content 'web\index.html' | Select-String "maps.googleapis.com"
if ($scriptLine -match 'MAPS_API_KEY_PLACEHOLDER') {
    Write-Host ""
    Write-Host "[ERROR] Script tag still has placeholder!" -ForegroundColor Red
    Write-Host "Line: $scriptLine" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "[OK] Keys injected successfully" -ForegroundColor Green
Write-Host "[OK] Verification passed - placeholder replaced" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: If maps don't load, try:" -ForegroundColor Yellow
Write-Host "  1. Hard refresh in browser (Ctrl+Shift+R or Ctrl+F5)" -ForegroundColor Yellow
Write-Host "  2. Clear browser cache" -ForegroundColor Yellow
Write-Host "  3. Check browser console for errors" -ForegroundColor Yellow
Write-Host ""
Write-Host "Starting Flutter Web..."
Write-Host "Press Ctrl+C to quit"
Write-Host ""

# Run Flutter and wait for it to exit
try {
    $flutterProcess = Start-Process -FilePath 'flutter' -ArgumentList 'run', '-d', 'chrome' -NoNewWindow -Wait -PassThru
} finally {
    # Restore backup only after Flutter exits
    Write-Host ""
    Write-Host "Cleaning up..."
    if (Test-Path 'web\index.html.backup') {
        Move-Item 'web\index.html.backup' 'web\index.html' -Force | Out-Null
        Write-Host "[OK] Restored original index.html" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "Done!"
}

