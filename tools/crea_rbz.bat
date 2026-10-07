@echo off
rem Crea dist\dagawasd-VERSIONE.rbz, da installare con il Gestore estensioni di SketchUp.
rem La versione sta in dagawasd.rb (VERSION) e va descritta in CHANGELOG.md.
title DagaWASD - Pacchetto .rbz
set "RUBY=ruby"
if exist "C:\Ruby32-x64\bin\ruby.exe" set "RUBY=C:\Ruby32-x64\bin\ruby.exe"
"%RUBY%" -E UTF-8 "%~dp0crea_rbz.rb"
if /i not "%~1"=="/nopause" pause
