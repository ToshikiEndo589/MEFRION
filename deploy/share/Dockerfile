FROM python:3.12-slim
WORKDIR /app
COPY deploy/share/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && useradd --uid 10001 --create-home mefrion
COPY backend/__init__.py backend/cloud_shares.py backend/shared_wsgi.py /app/backend/
COPY web/shared.css /app/web/shared.css
USER 10001
EXPOSE 8080
CMD ["gunicorn", "backend.shared_wsgi:application", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", "--timeout", "65", "--limit-request-line", "4096", "--limit-request-fields", "30", "--limit-request-field_size", "4096", "--max-requests", "1000", "--max-requests-jitter", "100", "--access-logfile", "/dev/null"]
