@echo off
rem Ricrea le icone PNG dagli SVG di pubblicazione\ (barra degli strumenti e scheda del Warehouse).
title DagaWASD - Icone
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rendi_icone.ps1"
if /i not "%~1"=="/nopause" pause
