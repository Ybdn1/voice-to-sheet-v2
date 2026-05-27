from fastapi import APIRouter, HTTPException, status

from app.schemas.auth import LoginRequest, LoginResponse, UserInfo
from app.services.auth_service import auth_service


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest) -> LoginResponse:
    user = auth_service.authenticate(payload.username, payload.password)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identifiant ou mot de passe invalide.",
        )

    token = auth_service.create_token(user)
    return LoginResponse(access_token=token, user=UserInfo(**user))
