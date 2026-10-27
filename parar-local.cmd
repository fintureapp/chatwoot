@echo off
rem Finture - para o Chatwoot local (dados preservados: banco, anexos, e-mails).
rem Uso, na raiz do projeto: .\parar-local.cmd   (para subir de novo: .\subir-local.cmd)
setlocal EnableExtensions
cd /d "%~dp0"
set "GITBASH="
for /f "delims=" %%G in ('where git 2^>nul') do if not defined GITBASH set "GITBASH=%%~dpG..\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
"%GITBASH%" script/local-dev stop
endlocal
