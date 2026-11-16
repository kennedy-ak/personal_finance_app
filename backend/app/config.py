"""Backend settings, read once from the environment (and backend/.env).

Everything has a workable default so `uvicorn app.main:app` runs out of the
box against a local SQLite file. Point DATABASE_URL at Postgres when you
outgrow it — the models use nothing SQLite-specific.
"""

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_BACKEND_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # SQLite in the backend folder by default; any SQLAlchemy URL works.
    database_url: str = f"sqlite:///{(_BACKEND_DIR / 'finance.db').as_posix()}"

    # HS256 signing key for access tokens. The default is fine for local
    # development only — set JWT_SECRET before exposing the server.
    jwt_secret: str = "change-me-in-backend-dotenv"
    jwt_expire_days: int = 30

    # The coach proxy. Without a key the /coach/complete endpoint answers 500
    # with a clear message, same as the old Edge Function did.
    openai_api_key: str = ""
    coach_model: str = "gpt-4o-mini"

    # Comma-separated origins for CORS. "*" is acceptable because auth is a
    # bearer token, not a cookie the browser attaches on its own.
    cors_origins: str = "*"


settings = Settings()
