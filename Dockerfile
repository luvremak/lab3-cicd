# Production Dockerfile for the mywebapp Simple Inventory service.
#
# Multi-purpose: used by docker compose for local dev AND built by CI for
# publication to GHCR. Layer order: base -> deps -> code (so app edits do
# not invalidate the dependency layer; see Lab 2 experiments 2-3).
#
# hadolint global ignore=DL3008  (no apt-get install in slim image)

FROM python:3.13-slim

WORKDIR /opt/mywebapp

# --- Dependencies (rarely change) -----------------------------------------
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Application code (often changes) -------------------------------------
COPY app/ app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Non-root runtime user (mirrors the "app" system user from Lab 1).
RUN useradd --system --no-create-home --shell /usr/sbin/nologin appuser
USER appuser

EXPOSE 5200

ENTRYPOINT ["/entrypoint.sh"]
