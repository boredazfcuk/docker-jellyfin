FROM jellyfin/jellyfin
MAINTAINER boredazfcuk

ARG jellyfin_version="10.5.6"
ARG app_dependencies="tzdata ca-certificates openssl iproute2 net-tools sqlite3"
ENV config_dir="/config"

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED *****" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install application dependencies" && \
   apt-get update && \
   apt-get install -y ${app_dependencies}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set permissions on launcher" && \
   chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh && \
   apt-get clean -y && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
   CMD /usr/local/bin/healthcheck.sh

VOLUME "${config_dir}"
WORKDIR "${config_dir}"

ENTRYPOINT /usr/local/bin/entrypoint.sh