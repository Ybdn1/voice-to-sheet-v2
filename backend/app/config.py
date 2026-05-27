import os
from pathlib import Path

from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

MISTRAL_API_KEY = os.getenv("MISTRAL_API_KEY", "")
MISTRAL_MODEL = os.getenv("MISTRAL_MODEL", "mistral-large-latest")

# Format optionnel :
# VOICE_TO_SHEET_USERS=agent1:password1,agent2:password2
VOICE_TO_SHEET_USERS = os.getenv("VOICE_TO_SHEET_USERS", "")

# Format optionnel :
# VOICE_TO_SHEET_CORS_ORIGINS=https://app.example.com,https://admin.example.com
VOICE_TO_SHEET_CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv("VOICE_TO_SHEET_CORS_ORIGINS", "").split(",")
    if origin.strip()
]
