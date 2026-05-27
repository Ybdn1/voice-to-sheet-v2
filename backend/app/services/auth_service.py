import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from app.config import VOICE_TO_SHEET_USERS


@dataclass(frozen=True)
class AuthUser:
    username: str
    password: str
    full_name: str
    role: str


class AuthService:
    def __init__(self) -> None:
        self._users = self._load_users()
        self._tokens: dict[str, dict[str, object]] = {}

    def _load_users(self) -> dict[str, AuthUser]:
        if VOICE_TO_SHEET_USERS.strip():
            users: dict[str, AuthUser] = {}
            for raw_entry in VOICE_TO_SHEET_USERS.split(","):
                username, password = raw_entry.split(":", maxsplit=1)
                clean_username = username.strip()
                users[clean_username] = AuthUser(
                    username=clean_username,
                    password=password.strip(),
                    full_name=clean_username.replace(".", " ").title(),
                    role="agent",
                )
            return users

        return {
            "agent.demo": AuthUser(
                username="agent.demo",
                password="demo1234",
                full_name="Agent Demo",
                role="agent",
            ),
            "superviseur.demo": AuthUser(
                username="superviseur.demo",
                password="demo1234",
                full_name="Superviseur Demo",
                role="supervisor",
            ),
        }

    def authenticate(self, username: str, password: str) -> dict[str, str] | None:
        user = self._users.get(username)
        if user is None or user.password != password:
            return None

        return {
            "username": user.username,
            "full_name": user.full_name,
            "role": user.role,
        }

    def create_token(self, user: dict[str, str]) -> str:
        token = secrets.token_urlsafe(32)
        expires_at = datetime.now(UTC) + timedelta(hours=12)
        self._tokens[token] = {"user": user, "expires_at": expires_at}
        return token

    def get_user_from_token(self, token: str) -> dict[str, str] | None:
        token_data = self._tokens.get(token)
        if token_data is None:
            return None

        expires_at = token_data["expires_at"]
        if not isinstance(expires_at, datetime) or expires_at <= datetime.now(UTC):
            self._tokens.pop(token, None)
            return None

        user = token_data["user"]
        if not isinstance(user, dict):
            return None

        return user


auth_service = AuthService()
