@echo off
setlocal enabledelayedexpansion
title DagaWASD - Installazione

rem ==================================================================
rem  Copia l'estensione nella cartella Plugins di ogni versione di
rem  SketchUp trovata. Le impostazioni non si toccano: stanno
rem  in %APPDATA%\DagaWASD\settings.json, fuori dall'estensione.
rem  Per distribuirla agli altri: tools\crea_rbz.bat (pacchetto .rbz).
rem ==================================================================

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

echo.
echo  ============================================
echo    DagaWASD  -  copia verso SketchUp
echo  ============================================
echo.
echo  Sorgente: %SRC%

rem --- i file sorgente ci sono tutti? ---------------------------------
set "MISSING="
for %%F in (main.rb panel.html attesa.html dagawasd.rb) do (
  if not exist "%SRC%\%%F" set "MISSING=!MISSING! %%F"
)
if not exist "%SRC%\icons" set "MISSING=!MISSING! icons\"
if not exist "%SRC%\lang"  set "MISSING=!MISSING! lang\"
if not exist "%SRC%\lib\config.rb" set "MISSING=!MISSING! lib\"
if not "!MISSING!"=="" (
  echo.
  echo  [X] File mancanti nella sorgente:!MISSING!
  echo      Installazione annullata.
  echo.
  pause
  exit /b 1
)

rem --- SketchUp aperto? Caricherebbe ancora la versione vecchia -------
tasklist /FI "IMAGENAME eq SketchUp.exe" 2>nul | find /I "SketchUp.exe" >nul
if not errorlevel 1 (
  echo.
  echo  [ATTENZIONE] SketchUp risulta APERTO.
  echo      I file verranno copiati lo stesso, ma per vedere le modifiche
  echo      devi chiudere e riaprire SketchUp.
)

rem --- una passata per ogni versione installata -----------------------
set "FOUND=0"
for /d %%V in ("%APPDATA%\SketchUp\SketchUp *") do (
  if exist "%%~fV\SketchUp\Plugins\" (
    set "FOUND=1"
    call :install "%%~fV\SketchUp\Plugins"
  )
)

if "%FOUND%"=="0" (
  echo.
  echo  [X] Nessuna cartella Plugins di SketchUp trovata in:
  echo      %APPDATA%\SketchUp
  echo      Copia i file a mano oppure controlla che SketchUp sia installato.
  echo.
  pause
  exit /b 1
)

echo.
echo  Fatto. Riavvia SketchUp per caricare la nuova versione.
echo.
pause
exit /b 0

rem ====================================================================
:install
set "DST=%~1"
set "EXT=%DST%\dagawasd"
echo.
echo  --^> %DST%
if not exist "%EXT%" mkdir "%EXT%"

copy /Y "%SRC%\main.rb"        "%EXT%\" >nul && echo      main.rb          aggiornato
copy /Y "%SRC%\panel.html"     "%EXT%\" >nul && echo      panel.html       aggiornato
copy /Y "%SRC%\attesa.html"    "%EXT%\" >nul && echo      attesa.html      aggiornato ^(finestra del video^)
rem attesa\ (il personaggio) si ricopia da zero, se c'e'
if exist "%EXT%\attesa" rmdir /S /Q "%EXT%\attesa"
if exist "%SRC%\attesa" xcopy /E /I /Y /Q "%SRC%\attesa" "%EXT%\attesa\" >nul && echo      attesa\          aggiornata ^(personaggio^)
copy /Y "%SRC%\dagawasd.rb"    "%DST%\" >nul && echo      dagawasd.rb      aggiornato
xcopy /E /I /Y /Q "%SRC%\icons" "%EXT%\icons\" >nul && echo      icons\           aggiornate
xcopy /E /I /Y /Q "%SRC%\lang"  "%EXT%\lang\"  >nul && echo      lang\            aggiornate ^(traduzioni^)
rem lib\ si ricopia da zero: un file tolto dalla sorgente non deve restare installato
if exist "%EXT%\lib" rmdir /S /Q "%EXT%\lib"
xcopy /E /I /Y /Q "%SRC%\lib"   "%EXT%\lib\"   >nul && echo      lib\             aggiornata ^(codice^)

goto :eof
