FROM jellyfin/jellyfin
MAINTAINER boredazfcuk

ARG jellyfin_version="10.7.5"
ARG app_dependencies="tzdata ca-certificates openssl iproute2 net-tools sqlite3"
ENV config_dir="/config"

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED FOR JELLYFIN *****" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install application dependencies" && \
   rm /etc/apt/sources.list.d/jellyfin.list && \
   apt-get update && \
   apt-get upgrade -y && \
   apt-get install apt-transport-https gnupg wget -y && \
   wget -O - https://repo.jellyfin.org/jellyfin_team.gpg.key | apt-key add - && \
   echo "deb [arch=$( dpkg --print-architecture )] https://repo.jellyfin.org/$( awk -F'=' '/^ID=/{ print $NF }' /etc/os-release ) $( awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release ) main" | tee /etc/apt/sources.list.d/jellyfin.list && \
   apt-get update && \
   apt-get install -y ${app_dependencies} && \
   apt-get clean -y && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 healthcheck.sh /usr/local/bin/healthcheck.sh

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
   CMD /usr/local/bin/healthcheck.sh

VOLUME "${config_dir}"
WORKDIR "${config_dir}"

ENTRYPOINT /usr/local/bin/entrypoint.sh
