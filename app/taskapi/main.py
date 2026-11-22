"""Task API: HTTP endpoints.

Operational endpoints (used by Docker, Kubernetes, and monitoring):
    GET /health  liveness:  "is the process alive?"     (never checks dependencies)
    GET /ready   readiness: "can it serve traffic now?"  (checks the database)

Business endpoints:
    GET    /tasks         list tasks
    POST   /tasks         create a task
    GET    /tasks/{id}    get one task
    PATCH  /tasks/{id}    update title and/or done
    DELETE /tasks/{id}    delete a task
"""

import logging
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import get_settings
from .db import check_database, get_session
from .models import Task
from .schemas import TaskCreate, TaskOut, TaskUpdate

settings = get_settings()

# 12-factor app, factor XI: logs go to stdout. Docker/Kubernetes collect them from there.
logging.basicConfig(
    level=settings.log_level.upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("taskapi")

app = FastAPI(title="Task API", version=settings.version)

SessionDep = Annotated[Session, Depends(get_session)]


# --------------------------------------------------------------------------- ops
@app.get("/health", tags=["ops"])
def health() -> dict:
    """Liveness probe. If this fails, the container should be restarted."""
    return {"status": "ok", "version": settings.version}


@app.get("/ready", tags=["ops"])
def ready(response: Response) -> dict:
    """Readiness probe. If this fails, stop sending traffic (but don't restart)."""
    if check_database():
        return {"status": "ready"}
    response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return {"status": "not ready", "reason": "database unreachable"}


# ------------------------------------------------------------------------- tasks
def _get_or_404(session: Session, task_id: int) -> Task:
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    return task


@app.get("/tasks", response_model=list[TaskOut], tags=["tasks"])
def list_tasks(session: SessionDep) -> list[Task]:
    return list(session.scalars(select(Task).order_by(Task.id)))


@app.get("/tasks/search", response_model=list[TaskOut], tags=["tasks"])
def search_tasks(
    q: Annotated[str, Query(min_length=1, max_length=200)], session: SessionDep
) -> list[Task]:
    """Case-insensitive search in task titles.

    icontains() sends q to the database as a bound PARAMETER, separately from the
    SQL text, so the database never executes it as SQL: no injection possible.
    autoescape=True also makes % and _ in q match literally instead of as wildcards.
    """
    stmt = select(Task).where(Task.title.icontains(q, autoescape=True)).order_by(Task.id)
    return list(session.scalars(stmt))


@app.post("/tasks", response_model=TaskOut, status_code=201, tags=["tasks"])
def create_task(payload: TaskCreate, session: SessionDep) -> Task:
    task = Task(title=payload.title)
    session.add(task)
    session.commit()
    session.refresh(task)  # load server-generated values (id, created_at)
    log.info("task created id=%s", task.id)
    return task


@app.get("/tasks/{task_id}", response_model=TaskOut, tags=["tasks"])
def get_task(task_id: int, session: SessionDep) -> Task:
    return _get_or_404(session, task_id)


@app.patch("/tasks/{task_id}", response_model=TaskOut, tags=["tasks"])
def update_task(task_id: int, payload: TaskUpdate, session: SessionDep) -> Task:
    task = _get_or_404(session, task_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(task, field, value)
    session.commit()
    session.refresh(task)
    log.info("task updated id=%s", task.id)
    return task


@app.delete("/tasks/{task_id}", status_code=204, tags=["tasks"])
def delete_task(task_id: int, session: SessionDep) -> Response:
    task = _get_or_404(session, task_id)
    session.delete(task)
    session.commit()
    log.info("task deleted id=%s", task_id)
    return Response(status_code=204)
