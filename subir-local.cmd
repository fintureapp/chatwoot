@echo off
rem Finture - sobe o Chatwoot local completo (Docker). Uso, na raiz do projeto:
rem   .\subir-local.cmd          (PowerShell)   |   subir-local.cmd   (cmd)   |   duplo clique
rem Para parar: .\parar-local.cmd     Guia: docs\LOCAL_DEVELOPMENT.md
setlocal EnableExtensions
cd /d "%~dp0"

rem 1. Git Bash (o bash.exe do PATH costuma ser o do WSL, que nao serve aqui)
set "GITBASH="
for /f "delims=" %%G in ('where git 2^>nul') do if not defined GITBASH set "GITBASH=%%~dpG..\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GITBASH%" (
  echo [finture-local] Git Bash nao encontrado. Instale o Git for Windows: https://git-scm.com/download/win
  goto :fim_erro
)

rem 2. Docker Desktop rodando? Se nao, abre e espera o motor (ate ~4 min)
docker info >nul 2>&1
if errorlevel 1 (
  echo [finture-local] Iniciando o Docker Desktop...
  if not exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
    echo [finture-local] Docker Desktop nao encontrado. Veja docs\LOCAL_DEVELOPMENT.md - Requisitos.
    goto :fim_erro
  )
  start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
  for /l %%i in (1,1,48) do (
    docker info >nul 2>&1 && goto :docker_ok
    timeout /t 5 /nobreak >nul
  )
  echo [finture-local] O Docker nao respondeu a tempo. Abra o Docker Desktop, espere ficar verde e rode de novo.
  goto :fim_erro
)
:docker_ok

rem 3. Sobe tudo: .env.local, imagem, dependencias, banco, seeds, Rails, Sidekiq, Vite e sincronizacao
"%GITBASH%" script/local-dev dev
if errorlevel 1 (
  echo.
  echo [finture-local] Algo falhou. Veja os logs com: "%GITBASH%" script/local-dev logs
  goto :fim_erro
)

start "" http://localhost:3000
echo.
echo [finture-local] Pronto! Login: admin@finture.example  senha: Finture@Local2026 (LOCAL_SEED_PASSWORD do .env.local)
echo [finture-local] Deixe este computador com o Docker aberto. Para parar: .\parar-local.cmd
endlocal
exit /b 0

:fim_erro
endlocal
pause
exit /b 1
