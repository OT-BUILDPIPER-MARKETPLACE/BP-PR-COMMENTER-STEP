FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    git \
    jq \
    curl \
    bash \
    coreutils \
    findutils \
    sed \
    gawk \
    grep \
    python3 \
    python3-venv \
    python3-pip && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        tabulate \
        cryptography


RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g buildpiper -d /home/buildpiper -m buildpiper && \
    chown -R buildpiper:buildpiper /home/buildpiper

ENV PATH="/opt/venv/bin:$PATH"

ENV ACTIVITY_SUB_TASK_CODE=""
ENV SLEEP_DURATION="5s"

WORKDIR /home/buildpiper/app

COPY --chown=buildpiper:buildpiper build.sh .
COPY --chown=buildpiper:buildpiper git_bulid_login.sh .
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

RUN chmod +x build.sh

USER buildpiper

ENTRYPOINT ["./build.sh"]