FROM eclipse-temurin:17-jre-alpine

# Upgrade OS packages to get latest security patches and install dependencies
RUN apk update --no-cache && \
    apk upgrade --no-cache && \
    apk add --no-cache curl tzdata expat && \
    addgroup -S appgroup -g 1001 && \
    adduser -S appuser -u 1001 -G appgroup

WORKDIR /app

# Copy pre-built JAR from CI pipeline
ARG JAR_FILE=target/*.jar
COPY --chown=appuser:appgroup ${JAR_FILE} app.jar

USER appuser:appgroup

EXPOSE 8080

# JVM container ergonomics for Kubernetes pod resource limits
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -Djava.security.egd=file:/dev/./urandom"

# Health check against Spring Boot Actuator
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
