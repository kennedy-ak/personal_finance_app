"""Password hashing and bearer-token auth — the replacement for Supabase Auth.

A signed HS256 JWT with the user id in `sub`, handed out at signup/login and
checked on every request. There is no refresh token: the access token simply
lives for JWT_EXPIRE_DAYS, which suits a personal app on your own server.
"""

from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import User

_bearer = HTTPBearer(auto_error=False)

ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


def create_token(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "iat": now,
        "exp": now + timedelta(days=settings.jwt_expire_days),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    if creds is None:
        raise HTTPException(status_code=401, detail="Sign in to continue.")
    try:
        payload = jwt.decode(creds.credentials, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Your session has expired. Sign in again.")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Sign in to continue.")

    user = db.get(User, payload.get("sub", ""))
    if user is None:
        raise HTTPException(status_code=401, detail="This account no longer exists.")
    return user
