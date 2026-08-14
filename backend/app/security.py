import secrets
from fastapi import Header, HTTPException
from sqlalchemy.orm import Session
from .models import User


def new_api_key() -> str:
    return secrets.token_hex(32)


def require_user(api_key: str = Header(alias="X-API-Key"), db: Session = None):
    if not api_key:
        raise HTTPException(status_code=401, detail="Missing API key")
    user = db.query(User).filter(User.api_key == api_key).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return user