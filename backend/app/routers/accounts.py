from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Account, User
from ..security import current_user
from ..serialize import account_row
from ..services.balances import recompute_account_balance

router = APIRouter(prefix="/accounts", tags=["accounts"])

KINDS = {"bank", "momo", "cash", "savings", "investment", "credit"}
LIQUIDITIES = {"liquid", "reserved", "locked"}


class AccountCreate(BaseModel):
    name: str
    opening_balance: float = 0
    kind: str = "bank"
    liquidity: str = "liquid"
    min_balance: float = 0
    purpose: str | None = None
    sort_order: int = 0


class AccountPatch(BaseModel):
    name: str | None = None
    kind: str | None = None
    liquidity: str | None = None
    min_balance: float | None = None
    purpose: str | None = None
    is_archived: bool | None = None
    sort_order: int | None = None
    opening_balance: float | None = None


def _own(db: Session, user: User, account_id: str) -> Account:
    account = db.get(Account, account_id)
    if account is None or account.user_id != user.id:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


@router.get("")
def list_accounts(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(Account)
            .where(Account.user_id == user.id)
            .order_by(Account.sort_order.asc(), Account.name.asc())
        )
        .scalars()
        .all()
    )
    return [account_row(a) for a in rows]


@router.post("")
def create_account(
    body: AccountCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    if body.kind not in KINDS:
        raise HTTPException(status_code=400, detail="Unknown account kind")
    if body.liquidity not in LIQUIDITIES:
        raise HTTPException(status_code=400, detail="Unknown liquidity")
    if body.min_balance < 0:
        raise HTTPException(status_code=400, detail="min_balance must be at least 0")

    duplicate = db.execute(
        select(Account).where(Account.user_id == user.id, Account.name == body.name)
    ).scalar_one_or_none()
    if duplicate is not None:
        raise HTTPException(status_code=409, detail="You already have an account with this name.")

    account = Account(
        user_id=user.id,
        name=body.name,
        opening_balance=body.opening_balance,
        balance=body.opening_balance,
        kind=body.kind,
        liquidity=body.liquidity,
        min_balance=body.min_balance,
        purpose=body.purpose or None,
        sort_order=body.sort_order,
    )
    db.add(account)
    db.commit()
    return account_row(account)


@router.patch("/{account_id}")
def update_account(
    account_id: str,
    body: AccountPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    account = _own(db, user, account_id)
    patch = body.model_dump(exclude_unset=True)

    if "kind" in patch and patch["kind"] not in KINDS:
        raise HTTPException(status_code=400, detail="Unknown account kind")
    if "liquidity" in patch and patch["liquidity"] not in LIQUIDITIES:
        raise HTTPException(status_code=400, detail="Unknown liquidity")

    opening_changed = False
    for key, value in patch.items():
        if key == "purpose":
            value = value or None
        if key == "opening_balance":
            opening_changed = Decimal(str(value)) != Decimal(str(account.opening_balance))
        setattr(account, key, value)

    if opening_changed:
        db.flush()
        recompute_account_balance(db, account.id)
    db.commit()
    return account_row(account)


@router.delete("/{account_id}")
def delete_account(
    account_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    account = _own(db, user, account_id)

    # Deleting the account cascades its transactions, and a cascaded transfer
    # row changes the balance of the account at its other end — settle those.
    from ..models import Transaction

    touched = set(
        db.execute(
            select(Transaction.account_id, Transaction.to_account_id).where(
                (Transaction.account_id == account_id)
                | (Transaction.to_account_id == account_id)
            )
        ).all()
    )
    others = {a for pair in touched for a in pair if a and a != account_id}

    db.delete(account)
    db.flush()
    for other in others:
        recompute_account_balance(db, other)
    db.commit()
    return {"ok": True}
