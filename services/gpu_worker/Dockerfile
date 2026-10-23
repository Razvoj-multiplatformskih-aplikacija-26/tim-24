FROM python:3.12-slim
WORKDIR /app
COPY hedrion_worker ./hedrion_worker
USER 65534:65534
ENV WORKER_HOST=0.0.0.0
EXPOSE 8091
CMD ["python", "-m", "hedrion_worker.server"]
