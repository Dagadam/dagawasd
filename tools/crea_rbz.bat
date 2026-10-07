@echo off
rem Crea in dist\ i due pacchetti da installare con il Gestore estensioni di SketchUp:
rem   dagawasd-VERSIONE.rbz            completo, con il ponte per Claude (per te)
rem   dagawasd-VERSIONE-warehouse.rbz  senza ponte, da firmare e caricare sull'Extension Warehouse
rem La versione sta in dagawasd.rb (VERSION) e va descritta in CHANGELOG.md.
title DagaWASD - Pacchetti .rbz
set "RUBY=ruby"
if exist "C:\Ruby32-x64\bin\ruby.exe" set "RUBY=C:\Ruby32-x64\bin\ruby.exe"
"%RUBY%" -E UTF-8 "%~dp0crea_rbz.rb" && "%RUBY%" -E UTF-8 "%~dp0crea_rbz.rb" --warehouse
if /i not "%~1"=="/nopause" pause
