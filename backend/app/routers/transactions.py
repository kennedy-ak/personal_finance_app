from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Account, Transaction, User
from ..security import current_user
from ..serialize import transaction_row
from ..services.balances import recompute_for_txn

router = APIRouter(prefix="/transactions", tags=["transactions"])

TYPES = {"Income", "Expense", "Transfer"}


class TxnCreate(BaseModel):
    account_id: str
    type: str
    amount: float
    category: str
    description: str | None = None
    date: date_type
    to_account_id: str | None = None


def _own_account(db: Session, user: User, account_id: str) -> Account:
    account = db.get(Account, account_id)
    if account is None or account.user_id != user.id:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


@router.get("")
def list_transactions(
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
    date_from: date_type | None = Query(default=None, alias="from"),
    date_to: date_type | None = Query(default=None, alias="to"),
):
    q = select(Transaction).where(Transaction.user_id == user.id)
    if date_from is not None:
        q = q.where(Transaction.date >= date_from)
    if date_to is not None:
        q = q.where(Transaction.date <= date_to)
    rows = (
        db.execute(
            q.order_by(
                Transaction.date.desc(),
                Transaction.created_at.desc(),
                Transaction.id.desc(),
            )
        )
        .scalars()
        .all()
    )
    return [transaction_row(t) for t in rows]


@router.post("")
def create_transaction(
    body: TxnCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    if body.type not in TYPES:
        raise HTTPException(status_code=400, detail="Unknown transaction type")
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be above zero")
    _own_account(db, user, body.account_id)

    to_account = body.to_account_id or None
    if body.type == "Transfer":
        if not to_account or to_account == body.account_id:
            raise HTTPException(
                status_code=400, detail="A transfer needs two different accounts."
            )
        _own_account(db, user, to_account)
    elif to_account:
        raise HTTPException(
            status_code=400, detail="Only transfers carry a destination account."
        )

    txn = Transaction(
        user_id=user.id,
        account_id=body.account_id,
        to_account_id=to_account,
        type=body.type,
        amount=body.amount,
        category=body.category,
        description=body.description or None,
        date=body.date,
    )
    db.add(txn)
    db.flush()
    recompute_for_txn(db, txn.account_id, txn.to_account_id)
    db.commit()
    return transaction_row(txn)


@router.delete("/{txn_id}")
def delete_transaction(
    txn_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    txn = db.get(Transaction, txn_id)
    if txn is None or txn.user_id != user.id:
        raise HTTPException(status_code=404, detail="Transaction not found")
    touched = (txn.account_id, txn.to_account_id)
    db.delete(txn)
    db.flush()
    recompute_for_txn(db, *touched)
    db.commit()
    return {"ok": True}
