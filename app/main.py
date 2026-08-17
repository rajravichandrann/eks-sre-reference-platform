import os
import time

from fastapi import FastAPI, HTTPException

app = FastAPI(
    title="EKS SRE Reference App",
    version="1.0.0",
)

APP_VERSION = os.getenv("APP_VERSION", "local")


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