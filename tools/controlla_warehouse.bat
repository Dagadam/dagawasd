@echo off
rem Controlla il pacchetto per l'Extension Warehouse con le regole di Trimble (rubocop-sketchup).
title DagaWASD - Controllo per l'Extension Warehouse
set "RUBY=ruby"
if exist "C:\Ruby32-x64\bin\ruby.exe" set "RUBY=C:\Ruby32-x64\bin\ruby.exe"
"%RUBY%" -E UTF-8 "%~dp0controlla_warehouse.rb"
if /i not "%~1"=="/nopause" pause
