from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Goal, User
from ..security import current_user
from ..serialize import goal_row

router = APIRouter(prefix="/goals", tags=["goals"])


class GoalCreate(BaseModel):
    name: str
    target_amount: float
    saved_amount: float = 0
    target_date: date_type | None = None
    account_id: str | None = None
    priority: int = 0


class GoalPatch(BaseModel):
    name: str | None = None
    target_amount: float | None = None
    saved_amount: float | None = None
    # Distinguishes "leave the date alone" (field absent) from "clear it"
    # (field present and null), matching the clients' clearTargetDate paths.
    target_date: date_type | None = None
    account_id: str | None = None
    priority: int | None = None
    is_active: bool | None = None


def _own(db: Session, user: User, goal_id: str) -> Goal:
    row = db.get(Goal, goal_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Goal not found")
    return row


@router.get("")
def list_goals(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(Goal)
            .where(Goal.user_id == user.id)
            .order_by(Goal.priority.asc(), Goal.created_at.asc())
        )
        .scalars()
        .all()
    )
    return [goal_row(g) for g in rows]


@router.post("")
def create_goal(
    body: GoalCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    if body.target_amount <= 0:
        raise HTTPException(status_code=400, detail="Target must be above zero")
    if body.saved_amount < 0:
        raise HTTPException(status_code=400, detail="Saved amount cannot be negative")

    row = Goal(
        user_id=user.id,
        name=body.name,
        target_amount=body.target_amount,
        saved_amount=body.saved_amount,
        target_date=body.target_date,
        account_id=body.account_id or None,
        priority=body.priority,
    )
    db.add(row)
    db.commit()
    return goal_row(row)


@router.patch("/{goal_id}")
def update_goal(
    goal_id: str,
    body: GoalPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    row = _own(db, user, goal_id)
    patch = body.model_dump(exclude_unset=True)
    if "saved_amount" in patch and patch["saved_amount"] is not None and patch["saved_amount"] < 0:
        patch["saved_amount"] = 0
    for key, value in patch.items():
        if key == "account_id":
            value = value or None
        setattr(row, key, value)
    db.commit()
    return goal_row(row)


@router.delete("/{goal_id}")
def delete_goal(goal_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = _own(db, user, goal_id)
    db.delete(row)
    db.commit()
    return {"ok": True}
