Write-Host "Aegishjalmar Icon Converter" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if we have the SVG file
if (Test-Path "assets\icon_dark.svg") {
    Write-Host "Found icon_dark.svg" -ForegroundColor Green
} else {
    Write-Host "icon_dark.svg not found!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "To change your app icon, you need to:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Convert SVG to PNG:" -ForegroundColor White
Write-Host "   Go to: https://convertio.co/svg-png/" -ForegroundColor Cyan
Write-Host "   Upload: assets\icon_dark.svg" -ForegroundColor Cyan
Write-Host "   Download as PNG (1024x1024 recommended)" -ForegroundColor Cyan
Write-Host "   Save as: assets\icon_dark.png" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Generate app icons:" -ForegroundColor White
Write-Host "   Run: flutter pub get" -ForegroundColor Cyan
Write-Host "   Run: flutter pub run flutter_launcher_icons:main" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Rebuild your app:" -ForegroundColor White
Write-Host "   Stop the current app" -ForegroundColor Cyan
Write-Host "   Run: flutter run" -ForegroundColor Cyan
Write-Host ""

# Open the SVG file in default browser
Write-Host "Opening icon_dark.svg in your browser..." -ForegroundColor Yellow
Start-Process "assets\icon_dark.svg"

Write-Host ""
Write-Host "Tip: The icon change requires a full rebuild, not just hot restart!" -ForegroundColor Magenta
Write-Host "" 