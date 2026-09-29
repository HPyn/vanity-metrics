FROM ubuntu:24.04

ARG POWERSHELL_VERSION=7.6.6
ENV DEBIAN_FRONTEND=noninteractive \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    POWERSHELL_UPDATECHECK=Off \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    HOME=/tmp

# Install a maintained PowerShell package rather than the deprecated PowerShell image.
# The Microsoft Ubuntu package is amd64; Compose declares that platform explicitly.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tzdata \
    && curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/microsoft.deb \
    && dpkg -i /tmp/microsoft.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends "powershell=${POWERSHELL_VERSION}-1.deb" \
    && apt-get purge -y --auto-remove curl \
    && rm -rf /var/lib/apt/lists/* /tmp/microsoft.deb \
    && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin worker

WORKDIR /app
COPY src/ /app/
USER 10001:10001
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["pwsh", "-NoLogo", "-NoProfile", "-File", "/app/Test-Health.ps1"]
ENTRYPOINT ["pwsh", "-NoLogo", "-NoProfile", "-File", "/app/Start-Worker.ps1"]
