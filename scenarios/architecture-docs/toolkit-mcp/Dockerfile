FROM python:3.12-slim
WORKDIR /app
COPY backend/pyproject.toml backend/pyproject.toml
COPY backend/src backend/src
COPY toolkit-mcp/requirements.txt toolkit-requirements.txt
RUN pip install --no-cache-dir ./backend -r toolkit-requirements.txt
COPY toolkit-mcp/app.py app.py
COPY toolkit-mcp/server.py server.py
COPY data/inventory data/inventory
COPY data/standard data/standard
RUN useradd --uid 10001 --create-home appuser
USER 10001
ENV INVENTORY_DIR=/app/data/inventory STANDARD_DIR=/app/data/standard
ENV STORAGE_MODE=blob AUTH_MODE=entra
EXPOSE 8080
CMD ["uvicorn", "app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
