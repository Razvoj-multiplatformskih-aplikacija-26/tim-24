FROM dart:3.13.5 AS build
WORKDIR /app

# Resolve only the pure Dart server graph; Flutter SDK is not needed in Docker.
COPY infrastructure/docker/server-workspace.pubspec.yaml ./pubspec.yaml
COPY pubspec.lock ./pubspec.lock
COPY packages/domain ./packages/domain
COPY packages/hedrion_contract ./packages/hedrion_contract
COPY packages/hedrion_mapping ./packages/hedrion_mapping
COPY services/api ./services/api
COPY apps/server ./apps/server
RUN dart pub get
RUN dart compile exe apps/server/bin/server.dart -o /app/hedrion-server
RUN mkdir /app/objects

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/hedrion-server /app/hedrion-server
COPY --from=build --chown=65532:65532 /app/objects /app/objects
COPY infrastructure/migrations /app/infrastructure/migrations
COPY infrastructure/seed /app/infrastructure/seed
WORKDIR /app
USER 65532:65532
EXPOSE 8080
CMD ["/app/hedrion-server"]
