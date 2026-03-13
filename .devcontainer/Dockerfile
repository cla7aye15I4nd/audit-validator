FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV VIRTUAL_ENV=/opt/venv
ENV PATH=/opt/venv/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    clang \
    clangd \
    cmake \
    curl \
    gdb \
    git \
    lld \
    lldb \
    llvm \
    make \
    ninja-build \
    nodejs \
    npm \
    openssh-client \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    sudo \
    unzip \
    vim \
    wget \
    zip \
    zlib1g-dev \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv "${VIRTUAL_ENV}" \
    && "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir --upgrade pip setuptools wheel \
    && "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir \
        anthropic \
        claude-code-sdk \
        ipython \
        openai \
        openai-agents \
        pydantic \
        pydantic-settings \
        pytest \
        python-dotenv \
        requests \
        rich \
        ruff \
        typer \
        uv

RUN if id -u ubuntu >/dev/null 2>&1; then \
        usermod -s /bin/bash -aG sudo ubuntu; \
    else \
        useradd -ms /bin/bash -G sudo ubuntu; \
    fi \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

RUN npm install -g @openai/codex

USER ubuntu

RUN curl -fsSL https://claude.ai/install.sh | bash

RUN curl -L code.kimi.com/install.sh | bash

ENV USER=ubuntu
ENV HOME=/home/ubuntu
ENV CARGO_HOME=/home/ubuntu/.cargo
ENV RUSTUP_HOME=/home/ubuntu/.rustup
ENV PATH=/home/ubuntu/.cargo/bin:/opt/venv/bin:${PATH}

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --profile default --default-toolchain stable \
    && rustup component add clippy rustfmt

WORKDIR /workspaces
