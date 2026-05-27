@echo off
REM Launch the FastAPI backend for local network access.

echo ================================================
echo   Backend VoiceToSheet - accessible en reseau
echo ================================================
echo.
echo URL locale (PC)       : http://localhost:8000
echo URL reseau (tel/TV)   : http://172.20.10.9:8000
echo.
echo Appuie sur Ctrl+C pour arreter
echo.

cd /d "%~dp0"
if not exist "venv\Scripts\python.exe" (
  echo ERREUR: venv\Scripts\python.exe introuvable.
  echo Cree ou reinstalle l environnement virtuel du backend.
  exit /b 1
)

venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
