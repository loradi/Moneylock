from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from ..db import SessionLocal
from ..models import User, Transaction
from ..schemas import SyncRequest, SyncResult, SyncTransaction

router = APIRouter()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _user(db: Session, api_key: str | None) -> User:
    if not api_key:
        raise HTTPException(status_code=401, detail="Missing API key")
    user = db.query(User).filter(User.api_key == api_key).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return user


@router.post("", response_model=SyncResult)
def push(body: SyncRequest, api_key: str | None = Header(default=None, alias="X-API-Key"),
         db: Session = Depends(get_db)):
    user = _user(db, api_key)
    inserted = duplicates = 0
    for tx in body.transactions:
        exists = db.query(Transaction).filter(
            Transaction.user_id == user.id,
            Transaction.dedup_hash == tx.dedup_hash).first()
        if exists:
            duplicates += 1
            continue
        db.add(Transaction(user_id=user.id, amount=tx.amount,
            currency=tx.currency, merchant=tx.merchant, category=tx.category,
            source=tx.source, raw_text=tx.raw_text, timestamp=tx.timestamp,
            dedup_hash=tx.dedup_hash))
        inserted += 1
    db.commit()
    return SyncResult(inserted=inserted, duplicates=duplicates)


@router.get("")
def pull(since: datetime | None = None,
         api_key: str | None = Header(default=None, alias="X-API-Key"),
         db: Session = Depends(get_db)):
    user = _user(db, api_key)
    q = db.query(Transaction).filter(Transaction.user_id == user.id)
    if since:
        q = q.filter(Transaction.timestamp >= since)
    rows = q.order_by(Transaction.timestamp.desc()).all()
    return {"transactions": [{
        "amount": r.amount, "currency": r.currency, "merchant": r.merchant,
        "category": r.category, "source": r.source, "raw_text": r.raw_text,
        "timestamp": r.timestamp.isoformat(), "dedup_hash": r.dedup_hash,
    } for r in rows]}