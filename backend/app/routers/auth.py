from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import User
from ..security import create_token, current_user, hash_password, verify_password
from ..serialize import user_row
from ..services.defaults import create_default_accounts, seed_default_categories

router = APIRouter(prefix="/auth", tags=["auth"])


class SignupBody(BaseModel):
    email: EmailStr
    password: str
    full_name: str | None = None


class LoginBody(BaseModel):
    email: EmailStr
    password: str


class ChangePasswordBody(BaseModel):
    current_password: str
    new_password: str


@router.post("/signup")
def signup(body: SignupBody, db: Session = Depends(get_db)):
    if len(body.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters.")

    email = body.email.lower().strip()
    exists = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if exists is not None:
        raise HTTPException(status_code=409, detail="An account with this email already exists.")

    name = (body.full_name or "").strip() or None
    user = User(email=email, password_hash=hash_password(body.password), full_name=name)
    db.add(user)
    db.flush()

    # What the Supabase signup trigger used to do.
    create_default_accounts(db, user.id)
    seed_default_categories(db, user.id)
    db.commit()

    return {"token": create_token(user.id), "user": user_row(user)}


@router.post("/login")
def login(body: LoginBody, db: Session = Depends(get_db)):
    email = body.email.lower().strip()
    user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=401,
            detail="That password does not match this email. Try again or reset it.",
        )
    return {"token": create_token(user.id), "user": user_row(user)}


@router.get("/me")
def me(user: User = Depends(current_user)):
    return user_row(user)


@router.post("/change-password")
def change_password(
    body: ChangePasswordBody,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    # 400, not 401 — the session is fine, the typed password is not, and a 401
    # would make the clients treat it as an expired session and sign out.
    if not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Your current password is not right.")
    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters.")
    user.password_hash = hash_password(body.new_password)
    db.add(user)
    db.commit()
    return {"ok": True}


@router.post("/password-reset")
def password_reset():
    # This server sends no email. Said plainly rather than pretending.
    raise HTTPException(
        status_code=501,
        detail=(
            "Password reset by email is not available on this server. "
            "Change your password from Settings while signed in."
        ),
    )
