@echo off
setlocal
title DagaWASD - Test
rem ==================================================================
rem  Lancia tutti i test del progetto:
rem    1. controllo di sintassi dei file Ruby
rem    2. test di fisica e materiali (tests\test_physics.rb)
rem    3. tasti, importazione e registro errori (tests\test_settings.rb)
rem    4. ponte per Claude, meteo e gamepad (test_bridge, test_sky, test_precip, test_clouds, test_gamepad)
rem    5. completezza delle traduzioni (tests\test_i18n.rb)
rem    6. pacchetti .rbz: si creano, si estraggono e si caricano (tests\test_rbz.rb),
rem       e regole SketchUp sul pacchetto per l'Extension Warehouse (se c'e' rubocop)
rem    7. test del pannello in un browser simulato (tests\panel)
rem  Serve Ruby 3.2 (C:\Ruby32-x64) e, per il pannello, Node.js.
rem  Questa cartella NON viene copiata in SketchUp da installa.bat.
rem ==================================================================

set "ROOT=%~dp0.."
set "RUBY=ruby"
if exist "C:\Ruby32-x64\bin\ruby.exe" set "RUBY=C:\Ruby32-x64\bin\ruby.exe"
set "FAIL=0"

echo.
echo  == Sintassi Ruby ==
"%RUBY%" -wc "%ROOT%\main.rb"        || set "FAIL=1"
for %%F in ("%ROOT%\lib\*.rb") do "%RUBY%" -wc "%%F" >nul || (echo  [X] %%~nxF & set "FAIL=1")
echo  lib\*.rb controllati
"%RUBY%" -wc "%ROOT%\dagawasd.rb" || set "FAIL=1"

echo.
echo  == Fisica e materiali ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_physics.rb" || set "FAIL=1"

echo.
echo  == Impostazioni, tasti e registro errori ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_settings.rb" || set "FAIL=1"

echo.
echo  == Bug corretti (regressioni) ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_regressions.rb" || set "FAIL=1"

echo.
echo  == Ponte per Claude ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_bridge.rb" || set "FAIL=1"

echo.
echo  == Cielo (sole, luna, stelle) ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_sky.rb" || set "FAIL=1"

echo.
echo  == Pioggia e neve ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_precip.rb" || set "FAIL=1"

echo.
echo  == Nuvole ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_clouds.rb" || set "FAIL=1"

echo.
echo  == Temporale, neve al suolo, situazioni ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_meteo_extra.rb" || set "FAIL=1"

echo.
echo  == Gamepad ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_gamepad.rb" || set "FAIL=1"

echo.
echo  == Percorsi ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_path.rb" || set "FAIL=1"

echo.
echo  == Traduzioni ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_i18n.rb" || set "FAIL=1"

echo.
echo  == Pacchetto .rbz ==
"%RUBY%" -E UTF-8 "%ROOT%\tests\test_rbz.rb" || set "FAIL=1"

echo.
echo  == Regole SketchUp per l'Extension Warehouse ==
where rubocop >nul 2>nul
if errorlevel 1 (
  echo  [salto] rubocop non installato ^(istruzioni in tools\controlla_warehouse.rb^)
) else (
  "%RUBY%" -E UTF-8 "%ROOT%\tools\controlla_warehouse.rb" || set "FAIL=1"
)

echo.
echo  == Pannello ==
where node >nul 2>nul
if errorlevel 1 (
  echo  [salto] Node.js non trovato
) else (
  if not exist "%ROOT%\tests\panel\node_modules\jsdom" (
    echo  Prima esecuzione: installo jsdom...
    pushd "%ROOT%\tests\panel" && call npm install --silent && popd
  )
  node "%ROOT%\tests\panel\test_panel.js" || set "FAIL=1"
)

echo.
if "%FAIL%"=="0" (echo  ===== TUTTO OK =====) else (echo  ===== CI SONO ERRORI =====)
echo.
if /i not "%~1"=="/nopause" pause
exit /b %FAIL%
