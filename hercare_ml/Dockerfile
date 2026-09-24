FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ENVIRONMENT=production \
    MODEL_PATH=/app/artifacts/peri_dep_baseline.joblib

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt \
    && useradd --create-home --uid 10001 hercare

COPY app ./app
COPY artifacts/peri_dep_baseline.joblib ./artifacts/peri_dep_baseline.joblib
COPY artifacts/peri_dep_baseline.json ./artifacts/peri_dep_baseline.json

USER hercare
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health', timeout=2)"

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001", "--workers", "1"]

