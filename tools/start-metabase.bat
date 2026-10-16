@echo off
rem Starts Metabase on http://127.0.0.1:3000 (local only, not reachable from the network).
setlocal
cd /d "%~dp0"
for /d %%D in (jdk-*-jre) do set "JAVA=%~dp0%%D\bin\java.exe"
set "MB_DB_FILE=%~dp0metabase-data\metabase"
set "MB_JETTY_HOST=127.0.0.1"
set "MB_JETTY_PORT=3000"
set "MB_ANON_TRACKING_ENABLED=false"
set "MB_CHECK_FOR_UPDATES=false"
if not exist "%~dp0metabase-data" mkdir "%~dp0metabase-data"
"%JAVA%" -Xmx2g -jar "%~dp0metabase.jar"
