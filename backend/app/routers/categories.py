from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Category, Transaction, User
from ..security import current_user
from ..serialize import category_row
from ..services.defaults import seed_default_categories

router = APIRouter(prefix="/categories", tags=["categories"])

KINDS = {"expense", "income"}


class CategoryCreate(BaseModel):
    name: str
    kind: str
    icon: str | None = None
    sort_order: int = 100


class CategoryPatch(BaseModel):
    icon: str | None = None
    is_hidden: bool | None = None
    sort_order: int | None = None


class RenameBody(BaseModel):
    new_name: str


def _own(db: Session, user: User, category_id: str) -> Category:
    row = db.get(Category, category_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Category not found")
    return row


def _txn_type_for(kind: str) -> str:
    return "Income" if kind == "income" else "Expense"


@router.get("")
def list_categories(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(Category)
            .where(Category.user_id == user.id)
            .order_by(Category.sort_order.asc(), Category.name.asc())
        )
        .scalars()
        .all()
    )
    return [category_row(c) for c in rows]


@router.post("")
def create_category(
    body: CategoryCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    if body.kind not in KINDS:
        raise HTTPException(status_code=400, detail="Unknown category kind")
    duplicate = db.execute(
        select(Category).where(
            Category.user_id == user.id,
            Category.kind == body.kind,
            Category.name == body.name,
        )
    ).scalar_one_or_none()
    if duplicate is not None:
        raise HTTPException(status_code=409, detail="You already have this category.")

    row = Category(
        user_id=user.id,
        name=body.name,
        kind=body.kind,
        icon=body.icon,
        sort_order=body.sort_order,
    )
    db.add(row)
    db.commit()
    return category_row(row)


@router.patch("/{category_id}")
def update_category(
    category_id: str,
    body: CategoryPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    row = _own(db, user, category_id)
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(row, key, value)
    db.commit()
    return category_row(row)


@router.post("/{category_id}/rename")
def rename_category(
    category_id: str,
    body: RenameBody,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Renames the category AND every transaction wearing the old label, in one
    transaction — the port of rename_category()."""
    row = _own(db, user, category_id)
    new_name = body.new_name.strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="A category needs a name.")
    if row.name == new_name:
        return category_row(row)

    old = row.name
    row.name = new_name
    txns = (
        db.execute(
            select(Transaction).where(
                Transaction.user_id == user.id,
                Transaction.category == old,
                Transaction.type == _txn_type_for(row.kind),
            )
        )
        .scalars()
        .all()
    )
    for t in txns:
        t.category = new_name
    db.commit()
    return category_row(row)


@router.get("/{category_id}/usage")
def usage_count(
    category_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    row = _own(db, user, category_id)
    n = db.execute(
        select(func.count()).where(
            Transaction.user_id == user.id,
            Transaction.category == row.name,
            Transaction.type == _txn_type_for(row.kind),
        )
    ).scalar_one()
    return {"count": int(n)}


@router.post("/restore-defaults")
def restore_defaults(user: User = Depends(current_user), db: Session = Depends(get_db)):
    seed_default_categories(db, user.id)
    db.commit()
    return {"ok": True}


@router.delete("/{category_id}")
def delete_category(
    category_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    row = _own(db, user, category_id)
    db.delete(row)
    db.commit()
    return {"ok": True}
