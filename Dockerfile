FROM eclipse-temurin:17-jre

LABEL maintainer="Jaspal Singh"

ENV SPRING_PROFILES_ACTIVE=prod

WORKDIR /app

# Copy JAR produced by Jenkins
COPY target/spring-petclinic-*.jar app.jar

# Run as non-root (best practice)
RUN useradd -r -u 1001 appuser && \
    chown appuser /app/app.jar

USER appuser

EXPOSE 8080

ENTRYPOINT ["java","-jar","/app/app.jar"]

