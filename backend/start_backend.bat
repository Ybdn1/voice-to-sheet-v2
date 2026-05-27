@echo off
REM Lance le backend FastAPI accessible depuis le réseau local (Wi-Fi)
REM Le backend sera joignable depuis le téléphone/TV via l'IP du PC

echo ================================================
echo   Backend VoiceToSheet - accessible en réseau
echo ================================================
echo.
echo URL locale (PC)       : http://localhost:8000
echo URL réseau (tel/TV)   : http://10.250.136.170:8000
echo.
echo Appuyez sur Ctrl+C pour arrêter
echo.

cd /d "%~dp0"
call venv\Scripts\activate.bat
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
