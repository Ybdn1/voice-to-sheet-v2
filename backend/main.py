from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import VOICE_TO_SHEET_CORS_ORIGINS
from app.routers.auth import router as auth_router
from app.routers.references import router as references_router
from app.routers.reports import router as reports_router


app = FastAPI(
    title="VoiceToSheet API",
    version="1.0.0",
    description="API backend pour l'application mobile VoiceToSheet.",
)

cors_options: dict = {
    "allow_methods": ["*"],
    "allow_headers": ["*"],
}

if VOICE_TO_SHEET_CORS_ORIGINS:
    # Origines explicites configurees (ex: web app hebergee) — cookies/credentials OK.
    cors_options["allow_origins"] = VOICE_TO_SHEET_CORS_ORIGINS
    cors_options["allow_credentials"] = True
else:
    # Pas d'origines configurees : API mobile/ouverte — on autorise tout.
    # (allow_credentials ne peut pas etre True avec allow_origins=["*"])
    cors_options["allow_origins"] = ["*"]

app.add_middleware(CORSMiddleware, **cors_options)

app.include_router(auth_router)
app.include_router(references_router)
app.include_router(reports_router)

@app.get("/health", tags=["health"])
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}
