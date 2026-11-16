"""Balance maintenance — the port of recompute_account_balance() and its
trigger from migration 0002.

balance = opening_balance
        + income - expense - transfers out + transfers in

Called explicitly after any write that touches transactions or an account's
opening balance, inside the same session, before commit.
"""

from decimal import Decimal

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from ..models import Account, Transaction


def recompute_account_balance(db: Session, account_id: str) -> None:
    account = db.get(Account, account_id)
    if account is None:
        return

    own = db.execute(
        select(
            func.coalesce(
                func.sum(
                    case(
                        (Transaction.type == "Income", Transaction.amount),
                        (Transaction.type == "Expense", -Transaction.amount),
                        (Transaction.type == "Transfer", -Transaction.amount),
                    )
                ),
                0,
            )
        ).where(Transaction.account_id == account_id)
    ).scalar_one()

    incoming = db.execute(
        select(func.coalesce(func.sum(Transaction.amount), 0)).where(
            Transaction.to_account_id == account_id,
            Transaction.type == "Transfer",
        )
    ).scalar_one()

    account.balance = Decimal(str(account.opening_balance)) + Decimal(str(own)) + Decimal(
        str(incoming)
    )


def recompute_for_txn(db: Session, *account_ids: str | None) -> None:
    """Settle every account a transaction row touches, once each."""
    for account_id in {a for a in account_ids if a}:
        recompute_account_balance(db, account_id)
