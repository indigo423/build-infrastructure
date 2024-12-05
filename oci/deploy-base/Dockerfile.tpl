###
# Stage building JICMP and JICMP6 using OpenJDK 8
###
FROM ${JDK8_BUILDER_IMAGE} AS jdk8-builder

RUN git config --global advice.detachedHead false && \
    git clone --depth 1 --branch "${JICMP_VERSION}" "${JICMP_GIT_REPO_URL}" /usr/src/jicmp

WORKDIR /usr/src/jicmp

RUN git submodule update --init --recursive --depth 1 && \
    autoreconf -fvi && \
    ./configure && \
    make -j1

# Checkout and build JICMP6
RUN git clone --depth 1 --branch "${JICMP6_VERSION}" "${JICMP6_GIT_REPO_URL}" /usr/src/jicmp6

WORKDIR /usr/src/jicmp6
RUN git submodule update --init --recursive --depth 1 && \
    autoreconf -fvi && \
    ./configure && \
    make -j1

###
# Stage building JRRD2 using OpenJDK 17
###
FROM ${JDK17_BUILDER_IMAGE} AS jdk17-builder

RUN git config --global advice.detachedHead false && \
    git clone --depth 1 --branch "${JRRD2_VERSION}" "${JRRD2_GIT_REPO_URL}" /usr/src/jrrd2

WORKDIR /usr/src/jrrd2

RUN make

###
# Generate base builder image
###
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# We need to install inetutils-ping to get the JNI Pinger to work.
# The JNI Pinger is tested with getprotobyname("icmp") and it is null if inetutils-ping is missing.
RUN apt-get update && \
    env DEBIAN_FRONTEND="noninteractive" apt-get install --no-install-recommends -y \
        ca-certificates \
        inetutils-ping \
        curl \
        ${JAVA_PKG} \
        rrdtool="${RRDTOOL_VERSION}" \
        rsync && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install confd
RUN if [ "$(uname -m)" = "x86_64" ]; then \
      curl -L "${CONFD_BASE_URL}/confd-${CONFD_VERSION}-linux-amd64.tar.gz" | tar xvz -C /usr/bin; \
    elif [ "$(uname -m)" = "armv7l" ]; then \
      curl -L "${CONFD_BASE_URL}/confd-${CONFD_VERSION}-linux-arm7.tar.gz" | tar xvz -C /usr/bin; \
    else \
      curl -L "${CONFD_BASE_URL}/confd-${CONFD_VERSION}-linux-arm64.tar.gz" | tar xvz -C /usr/bin; \
    fi && \
    mkdir -p /opt/prom-jmx-exporter && \
    curl "${PROM_JMX_EXPORTER_URL}" --output /opt/prom-jmx-exporter/jmx_prometheus_javaagent.jar

# Install JICMP
RUN mkdir -p /usr/lib/jni
COPY --from=jdk8-builder /usr/src/jicmp/.libs/libjicmp.la /usr/lib/jni/
COPY --from=jdk8-builder /usr/src/jicmp/.libs/libjicmp.so /usr/lib/jni/
COPY --from=jdk8-builder /usr/src/jicmp/jicmp.jar /usr/share/java

# Install JICMP6
COPY --from=jdk8-builder /usr/src/jicmp6/.libs/libjicmp6.la /usr/lib/jni/
COPY --from=jdk8-builder /usr/src/jicmp6/.libs/libjicmp6.so /usr/lib/jni/
COPY --from=jdk8-builder /usr/src/jicmp6/jicmp6.jar /usr/share/java

# Install JRRD2
COPY --from=jdk17-builder /usr/src/jrrd2/dist/jrrd2-api-*.jar /usr/share/java/jrrd2.jar
COPY --from=jdk17-builder /usr/src/jrrd2/dist/libjrrd2.so /usr/lib64/libjrrd2.so

# Prevent setup prompt
ENV DEBIAN_FRONTEND=noninteractive
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk"

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.title="Bluebird deploy image based on ${BASE_IMAGE}" \
      org.opencontainers.image.source="${VCS_SOURCE}" \
      org.opencontainers.image.revision="${VCS_REVISION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.vendor="Bluebird Community" \
      org.opencontainers.image.authors="'Bluebird' Community" \
      org.opencontainers.image.licenses="AGPL-3.0" \
      org.opennms.image.base="${BASE_IMAGE}" \
      org.opennms.image.java.version="${JAVA_MAJOR_VERSION}" \
      org.opennms.image.java.home="${JAVA_HOME}" \
      org.opennms.image.jicmp.version="${JICMP_VERSION}" \
      org.opennms.image.jicmp6.version="${JICMP6_VERSION}" \
      org.opennms.image.jrrd2.version="${JRRD2_VERSION}" \
      org.opennms.cicd.branch="${BUILD_BRANCH}" \
      org.opennms.cicd.buildurl="${BUILD_URL}" \
      org.opennms.cicd.buildnumber="${BUILD_NUMBER}"
