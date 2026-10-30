FROM python:3.12-slim
WORKDIR /app
COPY backend/pyproject.toml backend/pyproject.toml
COPY backend/src backend/src
RUN pip install --no-cache-dir ./backend
COPY data/inventory data/inventory
COPY data/standard data/standard
COPY data/docs data/docs
RUN useradd --uid 10001 --create-home appuser
USER 10001
ENV INVENTORY_DIR=/app/data/inventory STANDARD_DIR=/app/data/standard SEED_DIR=/app/data/docs
ENV STORAGE_MODE=blob AUTH_MODE=entra
EXPOSE 8000
CMD ["uvicorn", "docs_api.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
