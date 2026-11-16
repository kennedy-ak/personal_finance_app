from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Obligation, User
from ..security import current_user
from ..serialize import obligation_row

router = APIRouter(prefix="/obligations", tags=["obligations"])

DIRECTIONS = {"out", "in"}
CADENCES = {"once", "weekly", "biweekly", "monthly", "quarterly", "yearly"}


class ObligationCreate(BaseModel):
    name: str
    amount: float
    next_due: date_type
    direction: str = "out"
    cadence: str = "monthly"
    account_id: str | None = None
    category: str | None = None


class ObligationPatch(BaseModel):
    name: str | None = None
    amount: float | None = None
    next_due: date_type | None = None
    direction: str | None = None
    cadence: str | None = None
    account_id: str | None = None
    category: str | None = None
    is_active: bool | None = None


def _own(db: Session, user: User, obligation_id: str) -> Obligation:
    row = db.get(Obligation, obligation_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Obligation not found")
    return row


@router.get("")
def list_obligations(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(Obligation)
            .where(Obligation.user_id == user.id)
            .order_by(Obligation.next_due.asc())
        )
        .scalars()
        .all()
    )
    return [obligation_row(o) for o in rows]


@router.post("")
def create_obligation(
    body: ObligationCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    if body.direction not in DIRECTIONS:
        raise HTTPException(status_code=400, detail="Unknown direction")
    if body.cadence not in CADENCES:
        raise HTTPException(status_code=400, detail="Unknown cadence")
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be above zero")

    row = Obligation(
        user_id=user.id,
        name=body.name,
        direction=body.direction,
        amount=body.amount,
        cadence=body.cadence,
        next_due=body.next_due,
        account_id=body.account_id or None,
        category=body.category or None,
    )
    db.add(row)
    db.commit()
    return obligation_row(row)


@router.patch("/{obligation_id}")
def update_obligation(
    obligation_id: str,
    body: ObligationPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    row = _own(db, user, obligation_id)
    patch = body.model_dump(exclude_unset=True)
    if "direction" in patch and patch["direction"] not in DIRECTIONS:
        raise HTTPException(status_code=400, detail="Unknown direction")
    if "cadence" in patch and patch["cadence"] not in CADENCES:
        raise HTTPException(status_code=400, detail="Unknown cadence")
    for key, value in patch.items():
        if key in ("account_id", "category"):
            value = value or None
        setattr(row, key, value)
    db.commit()
    return obligation_row(row)


@router.delete("/{obligation_id}")
def delete_obligation(
    obligation_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    row = _own(db, user, obligation_id)
    db.delete(row)
    db.commit()
    return {"ok": True}
