"""API schemas (Pydantic): what clients may send and what they get back.

Validation happens here, before any database code runs. Invalid input -> HTTP 422.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    done: bool | None = None


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)  # allow building from ORM objects

    id: int
    title: str
    done: bool
    created_at: datetime
