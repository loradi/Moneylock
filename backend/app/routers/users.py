import uuid
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..db import SessionLocal
from ..models import User
from ..schemas import UserCreate, UserOut
from ..security import new_api_key

router = APIRouter()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@router.post("", response_model=UserOut)
def create_user(body: UserCreate, db: Session = Depends(get_db)):
    user = User(id=str(uuid.uuid4()), email=body.email, api_key=new_api_key())
    db.add(user)
    db.commit()
    return UserOut(id=user.id, api_key=user.api_key)