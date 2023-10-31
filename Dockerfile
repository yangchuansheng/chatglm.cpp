ARG BASE_IMAGE=ubuntu:20.04

FROM ${BASE_IMAGE} AS build

ARG CMAKE_ARGS="-DGGML_CUBLAS=OFF"

WORKDIR /chatglm.cpp

# apt
RUN \
    sed -e "s/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" \
        -e "s/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" -i /etc/apt/sources.list && \
    apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -yq --no-install-recommends \
        gcc g++ make python3-dev python3-pip python3-venv wget && \
    rm -rf /var/lib/apt/lists/*

# pip
RUN \
    python3 -m pip install --upgrade -i https://pypi.tuna.tsinghua.edu.cn/simple pip && \
    python3 -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    python3 -m pip install --no-cache-dir build cmake

RUN mkdir -p /app/default_models
RUN wget https://huggingface.co/Xorbits/chatglm2-6B-GGML/resolve/main/chatglm2-ggml-q5_1.bin -O /app/default_models/chatglm2-ggml-q5_1.bin

ARG PATH=${PATH}:/usr/local/bin

ADD . .

# build cpp binary
RUN \
    cmake -B build ${CMAKE_ARGS} && \
    cmake --build build -j --config Release

# build python binding
RUN \
    CMAKE_ARGS=${CMAKE_ARGS} python3 -m build --wheel

FROM ${BASE_IMAGE}

WORKDIR /chatglm.cpp

RUN \
    sed -e "s/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" \
        -e "s/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" -i /etc/apt/sources.list && \
    apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -yq --no-install-recommends \
        python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /chatglm.cpp/build/bin/main /chatglm.cpp/build/bin/main
COPY --from=build /chatglm.cpp/dist/ /chatglm.cpp/dist/
COPY --from=build /app /app

ADD examples examples

ENV MODEL=/app/default_models/chatglm2-ggml-q5_1.bin

RUN \
    python3 -m pip install --upgrade -i https://pypi.tuna.tsinghua.edu.cn/simple pip && \
    python3 -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    python3 -m pip install --no-cache-dir -f dist 'chatglm-cpp[api]' && \
    rm -rf dist

CMD ["uvicorn", "chatglm_cpp.openai_api:app", "--host", "0.0.0.0", "--port", "8000"]
