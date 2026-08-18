import os
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

app = FastAPI(
    title="EKS SRE Reference App",
    version="1.0.0",
)

APP_VERSION = os.getenv("APP_VERSION", "local")


HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "path", "status"],
)

HTTP_REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "path"],
    buckets=(
        0.005,
        0.01,
        0.025,
        0.05,
        0.1,
        0.25,
        0.5,
        1.0,
        2.5,
        5.0,
    ),
)


@app.middleware("http")
async def collect_http_metrics(request: Request, call_next):
    start_time = time.perf_counter()
    status_code = 500

    try:
        response = await call_next(request)
        status_code = response.status_code
        return response

    finally:
        duration = time.perf_counter() - start_time

        route = request.scope.get("route")

        if route is not None:
            path = route.path
        else:
            path = request.url.path

        # Don't let monitoring traffic pollute our application SLIs.
        excluded_paths = {
            "/metrics",
            "/healthz",
            "/readyz",
        }

        if path not in excluded_paths:
            HTTP_REQUESTS.labels(
                method=request.method,
                path=path,
                status=str(status_code),
            ).inc()

            HTTP_REQUEST_DURATION.labels(
                method=request.method,
                path=path,
            ).observe(duration)


@app.get("/")
def root():
    return {
        "service": "eks-sre-reference-app",
        "version": APP_VERSION,
        "status": "running",
    }


@app.get("/healthz")
def health():
    return {
        "status": "healthy",
    }


@app.get("/readyz")
def readiness():
    return {
        "status": "ready",
    }


@app.get("/work")
def work(delay_ms: int = 0, fail: bool = False):
    if delay_ms > 0:
        time.sleep(delay_ms / 1000)

    if fail:
        raise HTTPException(
            status_code=500,
            detail="Intentional failure",
        )

    return {
        "status": "success",
        "delay_ms": delay_ms,
    }


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )