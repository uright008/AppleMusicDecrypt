"""HTTP control plane for the Flutter and other non-interactive clients.

The server intentionally delegates all media handling to the existing Ripper.
It only translates JSON requests into the same operations exposed by the CLI.
"""

from __future__ import annotations

import argparse
import asyncio
from collections import deque
from contextlib import asynccontextmanager
from typing import Any, Optional

import grpc.aio
import uvicorn
from creart import add_creator, it
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, field_validator

from src.logger import LoggerCreator

add_creator(LoggerCreator)
from src.config import Config, ConfigCreator

add_creator(ConfigCreator)
from src.api import APICreator, WebAPI

add_creator(APICreator)
from src.grpc.manager import WMCreator, WrapperManager, WrapperManagerException

add_creator(WMCreator)
from src.measurer import Measurer, MeasurerCreator

add_creator(MeasurerCreator)

from src.flags import Flags
from src.rip import Ripper
from src.url import AppleMusicURL, URLType


SUPPORTED_CODECS = {
    "alac",
    "ec3",
    "ac3",
    "aac",
    "aac-binaural",
    "aac-downmix",
    "aac-legacy",
}


class DownloadRequest(BaseModel):
    urls: list[str] = Field(min_length=1, max_length=100)
    codec: str = "alac"
    language: Optional[str] = None
    force: bool = False
    include_participate_songs: bool = False

    @field_validator("urls")
    @classmethod
    def strip_urls(cls, value: list[str]) -> list[str]:
        urls = [url.strip() for url in value if url.strip()]
        if not urls:
            raise ValueError("At least one non-empty URL is required")
        return urls

    @field_validator("codec")
    @classmethod
    def validate_codec(cls, value: str) -> str:
        if value not in SUPPORTED_CODECS:
            raise ValueError(f"Unsupported codec: {value}")
        return value


class AuthLoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=1024)

    @field_validator("username")
    @classmethod
    def strip_username(cls, value: str) -> str:
        username = value.strip()
        if not username:
            raise ValueError("Username is required")
        return username


class AuthTwoFactorRequest(BaseModel):
    username: str = Field(min_length=1, max_length=320)
    code: str = Field(min_length=1, max_length=32)

    @field_validator("username", "code")
    @classmethod
    def strip_value(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Value cannot be empty")
        return stripped


class AuthStateError(Exception):
    pass


class LoginAttempt:
    def __init__(self, username: str) -> None:
        self.username = username
        self.two_factor_requested = asyncio.Event()
        self.codes: asyncio.Queue[str] = asyncio.Queue(maxsize=1)
        self.task: Optional[asyncio.Task] = None


class ServerState:
    def __init__(self) -> None:
        self.ripper: Optional[Ripper] = None
        self.decrypt_stream_task: Optional[asyncio.Task] = None
        self.dispatch_tasks: set[asyncio.Task] = set()
        self.history: deque[dict[str, Any]] = deque(maxlen=200)
        self.cancelled_ids: set[str] = set()
        self.authenticated_users: set[str] = set()
        self.login_attempt: Optional[LoginAttempt] = None
        self.auth_lock = asyncio.Lock()

    async def start(self) -> None:
        self.ripper = Ripper()
        self._attach_task_observers()
        it(WebAPI).init()
        await it(WrapperManager).init(it(Config).instance.url, it(Config).instance.secure)
        self.decrypt_stream_task = asyncio.create_task(
            it(WrapperManager).decrypt_init(
                on_success=self.ripper.on_decrypt_success,
                on_failure=self.ripper.on_decrypt_failed,
            )
        )
        self.decrypt_stream_task.add_done_callback(self._consume_background_result)

    async def stop(self) -> None:
        if self.login_attempt and self.login_attempt.task:
            self.login_attempt.task.cancel()
            await asyncio.gather(self.login_attempt.task, return_exceptions=True)
        for task in list(self.dispatch_tasks):
            task.cancel()
        if self.decrypt_stream_task:
            self.decrypt_stream_task.cancel()
        await asyncio.gather(*self.dispatch_tasks, return_exceptions=True)
        if self.decrypt_stream_task:
            await asyncio.gather(self.decrypt_stream_task, return_exceptions=True)
        await it(WebAPI).client.aclose()

    def _attach_task_observers(self) -> None:
        """Keep lightweight history and cancellation handles without changing Ripper."""
        assert self.ripper is not None
        manager = self.ripper.download_manager
        original_register = manager.register_task
        original_unregister = manager.unregister_task

        async def register(task: Any) -> None:
            # Task is a normal dataclass (not slotted), so a server-only handle is safe.
            task.server_coro = asyncio.current_task()
            await original_register(task)

        async def unregister(task: Any) -> None:
            snapshot = self.task_to_dict(task)
            if task.adamId in self.cancelled_ids:
                snapshot["status"] = "KILLED"
                snapshot["error"] = "Cancelled by user"
                self.cancelled_ids.discard(task.adamId)
            self.history.appendleft(snapshot)
            await original_unregister(task)

        manager.register_task = register
        manager.unregister_task = unregister

    @staticmethod
    def task_to_dict(task: Any) -> dict[str, Any]:
        metadata = getattr(task, "metadata", None)
        return {
            "adamId": task.adamId,
            "title": getattr(metadata, "title", None),
            "artist": getattr(metadata, "artist", None),
            "album": getattr(metadata, "album", None),
            "status": str(task.status),
            "error": str(task.error) if task.error else None,
        }

    def all_tasks(self) -> list[dict[str, Any]]:
        assert self.ripper is not None
        active = [
            self.task_to_dict(task)
            for task in self.ripper.download_manager.adam_id_task_mapping.values()
        ]
        return active + list(self.history)

    def schedule(self, coro: Any, label: str) -> None:
        task = asyncio.create_task(coro)
        self.dispatch_tasks.add(task)

        def finish(completed: asyncio.Task) -> None:
            self.dispatch_tasks.discard(completed)
            try:
                error = completed.exception()
            except asyncio.CancelledError:
                return
            if error:
                self.history.appendleft(
                    {
                        "adamId": label,
                        "title": None,
                        "artist": None,
                        "album": None,
                        "status": "FAILED",
                        "error": str(error),
                    }
                )

        task.add_done_callback(finish)

    @staticmethod
    def _consume_background_result(task: asyncio.Task) -> None:
        try:
            task.exception()
        except asyncio.CancelledError:
            pass

    def _auth_payload(
        self, status: str, username: Optional[str] = None
    ) -> dict[str, Any]:
        return {
            "status": status,
            "username": username,
            "authenticatedUsers": sorted(self.authenticated_users),
        }

    async def _await_login_transition(
        self, attempt: LoginAttempt, timeout: float
    ) -> dict[str, Any]:
        assert attempt.task is not None
        two_factor_wait = asyncio.create_task(attempt.two_factor_requested.wait())
        try:
            done, _ = await asyncio.wait(
                {attempt.task, two_factor_wait},
                timeout=timeout,
                return_when=asyncio.FIRST_COMPLETED,
            )
        finally:
            if not two_factor_wait.done():
                two_factor_wait.cancel()
                await asyncio.gather(two_factor_wait, return_exceptions=True)

        if attempt.task in done:
            try:
                await attempt.task
            except Exception:
                if self.login_attempt is attempt:
                    self.login_attempt = None
                raise
            self.authenticated_users.add(attempt.username)
            if self.login_attempt is attempt:
                self.login_attempt = None
            return self._auth_payload("authenticated", attempt.username)
        if attempt.two_factor_requested.is_set():
            return self._auth_payload("requires_2fa", attempt.username)
        return self._auth_payload("pending", attempt.username)

    async def auth_status(self) -> dict[str, Any]:
        attempt = self.login_attempt
        if attempt:
            return await self._await_login_transition(attempt, timeout=0)
        status = "authenticated" if self.authenticated_users else "signed_out"
        return self._auth_payload(status)

    async def start_login(self, username: str, password: str) -> dict[str, Any]:
        async with self.auth_lock:
            if self.login_attempt:
                current = await self._await_login_transition(
                    self.login_attempt, timeout=0
                )
                if current["status"] in {"pending", "requires_2fa"}:
                    raise AuthStateError(
                        f"Login already in progress for {self.login_attempt.username}"
                    )
            attempt = LoginAttempt(username)

            async def on_two_factor(_: str, __: str) -> str:
                attempt.two_factor_requested.set()
                code = await attempt.codes.get()
                attempt.two_factor_requested.clear()
                return code

            attempt.task = asyncio.create_task(
                it(WrapperManager).login(username, password, on_two_factor)
            )
            self.login_attempt = attempt
        return await self._await_login_transition(attempt, timeout=45)

    async def submit_two_factor(
        self, username: str, code: str
    ) -> dict[str, Any]:
        async with self.auth_lock:
            attempt = self.login_attempt
            if not attempt or attempt.username != username:
                raise AuthStateError("No matching login is waiting for a code")
            if attempt.task and attempt.task.done():
                return await self._await_login_transition(attempt, timeout=0)
            if not attempt.two_factor_requested.is_set():
                raise AuthStateError("The login has not requested a 2FA code")
            if attempt.codes.full():
                raise AuthStateError("A 2FA code is already being processed")
            await attempt.codes.put(code)
        return await self._await_login_transition(attempt, timeout=60)

    async def logout_account(self, username: str) -> dict[str, Any]:
        await it(WrapperManager).logout(username)
        self.authenticated_users.discard(username)
        status = "authenticated" if self.authenticated_users else "signed_out"
        return self._auth_payload(status, username)

    async def dispatch_url(self, raw_url: str, request: DownloadRequest) -> None:
        assert self.ripper is not None
        url = AppleMusicURL.parse_url(raw_url)
        if not url:
            real_url = await it(WebAPI).get_real_url(raw_url)
            url = AppleMusicURL.parse_url(real_url)
        if not url:
            raise ValueError(f"Illegal or unsupported Apple Music URL: {raw_url}")

        flags = Flags(
            force_save=request.force,
            language=request.language or it(Config).region.language,
            include_participate_in_works=request.include_participate_songs,
        )
        if url.type == URLType.Song:
            await self.ripper.rip_song(url, request.codec, flags)
        elif url.type == URLType.Album:
            await self.ripper.rip_album(url, request.codec, flags)
        elif url.type == URLType.Artist:
            await self.ripper.rip_artist(url, request.codec, flags)
        elif url.type == URLType.Playlist:
            await self.ripper.rip_playlist(url, request.codec, flags)
        else:
            raise ValueError(f"Unsupported Apple Music URL type: {url.type}")


state = ServerState()


@asynccontextmanager
async def lifespan(_: FastAPI):
    await state.start()
    yield
    await state.stop()


app = FastAPI(
    title="AppleMusicDecrypt API",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/api/v1/health")
async def health() -> dict[str, Any]:
    try:
        it(WrapperManager).status.cache_invalidate()
        status = await it(WrapperManager).status()
        return {
            "ready": status.ready,
            "regions": list(status.regions),
            "manager": it(Config).instance.url,
            "authenticatedUsers": sorted(state.authenticated_users),
        }
    except grpc.aio.AioRpcError as exc:
        raise HTTPException(status_code=503, detail="wrapper-manager is unavailable") from exc


@app.get("/api/v1/auth")
async def auth_status() -> dict[str, Any]:
    try:
        return await state.auth_status()
    except WrapperManagerException as exc:
        raise HTTPException(status_code=401, detail=exc.msg or "Login failed") from exc
    except grpc.aio.AioRpcError as exc:
        raise HTTPException(status_code=503, detail="wrapper-manager is unavailable") from exc


@app.post("/api/v1/auth/login")
async def login(request: AuthLoginRequest) -> dict[str, Any]:
    try:
        return await state.start_login(request.username, request.password)
    except AuthStateError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except WrapperManagerException as exc:
        raise HTTPException(status_code=401, detail=exc.msg or "Login failed") from exc
    except grpc.aio.AioRpcError as exc:
        raise HTTPException(status_code=503, detail="wrapper-manager is unavailable") from exc


@app.post("/api/v1/auth/2fa")
async def submit_two_factor(request: AuthTwoFactorRequest) -> dict[str, Any]:
    try:
        return await state.submit_two_factor(request.username, request.code)
    except AuthStateError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except WrapperManagerException as exc:
        raise HTTPException(status_code=401, detail=exc.msg or "2FA failed") from exc
    except grpc.aio.AioRpcError as exc:
        raise HTTPException(status_code=503, detail="wrapper-manager is unavailable") from exc


@app.delete("/api/v1/auth/{username}")
async def logout(username: str) -> dict[str, Any]:
    try:
        return await state.logout_account(username)
    except WrapperManagerException as exc:
        raise HTTPException(status_code=400, detail=exc.msg or "Logout failed") from exc
    except grpc.aio.AioRpcError as exc:
        raise HTTPException(status_code=503, detail="wrapper-manager is unavailable") from exc


@app.post("/api/v1/downloads", status_code=202)
async def create_download(request: DownloadRequest) -> dict[str, Any]:
    for url in request.urls:
        state.schedule(state.dispatch_url(url, request), url)
    return {"accepted": request.urls, "codec": request.codec}


@app.get("/api/v1/tasks")
async def list_tasks() -> dict[str, Any]:
    return {
        "tasks": state.all_tasks(),
        "downloadSpeed": it(Measurer).download_speed(),
        "decryptSpeed": it(Measurer).decrypt_speed(),
        "running": it(Measurer).tasks_count(),
    }


@app.delete("/api/v1/tasks/{adam_id}")
async def cancel_task(adam_id: str) -> dict[str, str]:
    assert state.ripper is not None
    task = state.ripper.download_manager.get_task(adam_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found or already completed")
    coro = getattr(task, "server_coro", None)
    if not coro:
        raise HTTPException(status_code=409, detail="Task cannot be cancelled")
    state.cancelled_ids.add(adam_id)
    coro.cancel()
    return {"adamId": adam_id, "status": "KILLED"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the AppleMusicDecrypt local API")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=10020, type=int)
    parser.add_argument(
        "--manager-url",
        help="Override the wrapper-manager gRPC host:port from config.toml",
    )
    manager_security = parser.add_mutually_exclusive_group()
    manager_security.add_argument(
        "--manager-secure", dest="manager_secure", action="store_true"
    )
    manager_security.add_argument(
        "--manager-insecure", dest="manager_secure", action="store_false"
    )
    parser.set_defaults(manager_secure=None)
    args = parser.parse_args()
    if args.manager_url:
        it(Config).instance.url = args.manager_url
    if args.manager_secure is not None:
        it(Config).instance.secure = args.manager_secure
    uvicorn.run(app, host=args.host, port=args.port, reload=False)


if __name__ == "__main__":
    main()
