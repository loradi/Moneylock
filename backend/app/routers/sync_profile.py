import json
from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from ..db import SessionLocal
from ..models import SyncProfile
from ..schemas import SyncProfileRequest
from .sync import _user

router = APIRouter()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@router.get("")
def pull_profile(
    api_key: str | None = Header(default=None, alias="X-API-Key"),
    db: Session = Depends(get_db),
):
    user = _user(db, api_key)
    state = db.get(SyncProfile, user.id)
    return {"profile": json.loads(state.payload) if state else None}


@router.put("")
def push_profile(
    body: SyncProfileRequest,
    api_key: str | None = Header(default=None, alias="X-API-Key"),
    db: Session = Depends(get_db),
):
    user = _user(db, api_key)
    state = db.get(SyncProfile, user.id)
    payload = json.dumps(body.profile, separators=(",", ":"))
    if state is None:
        db.add(SyncProfile(user_id=user.id, payload=payload))
    else:
        state.payload = payload
    db.commit()
    return {"ok": True}
