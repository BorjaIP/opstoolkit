# syntax=docker/dockerfile:1.4
FROM python:3.12-slim AS base

# Enable BuildKit-specific features
ENV APP_ROOT=/opt/app \
    PYTHONPATH=/opt/app \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=UTF-8 \
    PIP_NO_CACHE_DIR=off \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8

WORKDIR ${APP_ROOT}

# Install system dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Create non-root user early
RUN useradd -u 1001 appuser

# Pre-copy only requirements
COPY requirements/requirements.txt /tmp/requirements.txt

# Install Python dependencies using cache for pip
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip \
 && python -m pip install -r /tmp/requirements.txt

# Copy application code
COPY --chown=1001:0 . .

# Set permissions (optional if needed)
RUN chown -R appuser:appuser ${APP_ROOT}

# Switch to non-root user
USER appuser

EXPOSE 8080

CMD ["uvicorn", "app", "--host", "0.0.0.0", "--port", "8080"]
