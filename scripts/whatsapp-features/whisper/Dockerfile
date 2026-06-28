# syntax=docker/dockerfile:1.7
# Layer whisper.cpp + ffmpeg + a ggml model onto a NanoClaw agent-group image so
# voice-note transcription needs no on-demand install and no runtime model
# download (agent containers run under egress lockdown — they can't fetch a
# model at runtime). Built FROM the agent base image; tag the result as the
# target group's image so its spawns pick it up. Scoped to one group.
ARG BASE
ARG MODEL=base

# ---- builder: compile whisper.cpp statically + fetch the model --------------
FROM ${BASE} AS whisper-builder
ARG MODEL
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git
WORKDIR /opt/whisper.cpp
# Static libwhisper/ggml so only the single binary (plus libstdc++/libgomp) is
# needed in the final image.
RUN cmake -B build -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF \
 && cmake --build build -j"$(nproc)" --config Release --target whisper-cli
RUN bash ./models/download-ggml-model.sh ${MODEL}

# ---- final: base image + ffmpeg + whisper-cli + model -----------------------
FROM ${BASE}
ARG MODEL
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg libgomp1 \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/whisper/models
COPY --from=whisper-builder /opt/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli
COPY --from=whisper-builder /opt/whisper.cpp/models/ggml-${MODEL}.bin /opt/whisper/models/ggml-${MODEL}.bin
RUN chmod +x /usr/local/bin/whisper-cli
USER node
