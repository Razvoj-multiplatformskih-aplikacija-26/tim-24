FROM python:3.12-alpine
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# The fake provider uses only Python's standard library and no GPU packages.
COPY services/gpu_worker/hedrion_worker ./hedrion_worker
USER 65532:65532
EXPOSE 8091
CMD ["python", "-m", "hedrion_worker.server"]
