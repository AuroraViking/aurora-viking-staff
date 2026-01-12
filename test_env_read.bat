@echo off
echo Testing .env file reading...
echo.

echo Contents of .env file:
type .env
echo.
echo.

echo Reading GOOGLE_MAPS_API_KEY...
for /f "tokens=2 delims==" %%a in ('findstr /B "GOOGLE_MAPS_API_KEY=" .env') do (
    echo Found: %%a
    set "TEST_KEY=%%a"
)

echo.
echo TEST_KEY variable: %TEST_KEY%
echo Length: %TEST_KEY:~0,20%...

pause


