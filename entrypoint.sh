#!/bin/bash

##### Functions #####
Initialise(){
   IFS=,
   lan_ip="$(hostname -i)"
   docker_lan_ip_subnet="$(ip -4 route | grep "${lan_ip}" | grep -v via | awk '{print $1}')"
   search_domain="$(grep search "/etc/resolv.conf" | awk '{print$2}')"
   server_name="$(hostname)"
   server_name="${server_name%%.${search_domain}}.${search_domain}"
   if [ -z "${media_access_domain}" ]; then media_access_domain="${lan_ip}"; fi
   echo
   echo "$(date '+%c') INFO:    ***** Starting application container *****"
   echo "$(date '+%c') INFO:    $(cat /etc/*-release | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g' | sed 's/"//g')"
   echo "$(date '+%c') INFO:    Username: ${stack_user:=stackman}:${user_id:=1000}"
   echo "$(date '+%c') INFO:    Password: ${stack_password:=Skibidibbydibyodadubdub}"
   echo "$(date '+%c') INFO:    Group: ${group:=jellyfin}:${group_id:=1000}"
   echo "$(date '+%c') INFO:    Configuration directory: ${config_dir:=/config}"
   echo "$(date '+%c') INFO:    Server name: ${server_name}"
   echo "$(date '+%c') INFO:    Media Access Domain: ${media_access_domain}"
   echo "$(date '+%c') INFO:    Web root: ${jellyfin_web_root:=/}"
   echo "$(date '+%c') INFO:    HTTP port: ${jellyfin_http_port:=8096}"
   echo "$(date '+%c') INFO:    Host network: ${host_lan_ip_subnet}"
   echo "$(date '+%c') INFO:    Docker network: ${docker_lan_ip_subnet}"
}

CheckOpenVPNPIA(){
   if [ "${openvpnpia_enabled}" ]; then
      echo "$(date '+%c') INFO:    OpenVPNPIA is enabled. Wait for VPN to connect"
      vpn_adapter="$(ip addr | grep tun.$ | awk '{print $7}')"
      while [ -z "${vpn_adapter}" ]; do
         vpn_adapter="$(ip addr | grep tun.$ | awk '{print $7}')"
         sleep 5
      done
      echo "$(date '+%c') INFO:    VPN adapter available: ${vpn_adapter}"
   else
      echo "$(date '+%c') INFO:    OpenVPNPIA is not enabled"
   fi
}

CreateGroup(){
   if [ "$(grep -c "^${group}:x:${group_id}:" "/etc/group")" -eq 1 ]; then
      echo "$(date '+%c') INFO:    Group, ${group}:${group_id}, already created"
   else
      if [ "$(grep -c "^${group}:" "/etc/group")" -eq 1 ]; then
         echo "$(date '+%c') ERROR:   Group name, ${group}, already in use - exiting"
         sleep 120
         exit 1
      elif [ "$(grep -c ":x:${group_id}:" "/etc/group")" -eq 1 ]; then
         if [ "${force_gid}" = "True" ]; then
            group="$(grep ":x:${group_id}:" /etc/group | awk -F: '{print $1}')"
            echo "$(date '+%c') WARNING: Group id, ${group_id}, already exists - continuing as force_gid variable has been set. Group name to use: ${group}"
         else
            echo "$(date '+%c') ERROR:   Group id, ${group_id}, already in use - exiting"
            sleep 120
            exit 1
         fi
      else
         echo "$(date '+%c') INFO:    Creating group ${group}:${group_id}"
         addgroup --quiet --gid "${group_id}" --group "${group}"
      fi
   fi
}

CreateUser(){
   if [ "$(grep -c "^${user}:x:${user_id}:${group_id}" "/etc/passwd")" -eq 1 ]; then
      echo "$(date '+%c') INFO     User, ${user}:${user_id}, already created"
   else
      if [ "$(grep -c "^${user}:" "/etc/passwd")" -eq 1 ]; then
         echo "$(date '+%c') ERROR    User name, ${user}, already in use - exiting"
         sleep 120
         exit 1
      elif [ "$(grep -c ":x:${user_id}:$" "/etc/passwd")" -eq 1 ]; then
         echo "$(date '+%c') ERROR    User id, ${user_id}, already in use - exiting"
         sleep 120
         exit 1
      else
         echo "$(date '+%c') INFO     Creating user ${user}:${user_id}"
         adduser --quiet --system --shell /bin/bash --no-create-home --disabled-login --ingroup "${group}" --uid "${user_id}" "${stack_user}"
      fi
   fi
}

SetOwnerAndGroup(){
   echo "$(date '+%c') INFO:    Correct owner and group of application files, if required"
   find "${config_dir}" ! -user "${stack_user}" -exec chown "${stack_user}" {} \;
   find "${config_dir}" ! -group "${group}" -exec chgrp "${group}" {} \;
   find "/media/" ! -user "${stack_user}" -exec chown "${stack_user}" {} \;
   find "/media/" ! -group "${group}" -exec chgrp "${group}" {} \;
}

CleanTranscodesdirectory(){
   echo "$(date '+%c') INFO:    Clean transcodes temporary directory"
   find "/media/" -type f -delete {} \;
   find "/media/" -type d -delete {} \;
}

Configure(){
   if [ -f "${config_dir}/config/system.xml" ]; then
      echo "$(date '+%c') INFO:    Configure Jellyfin dynamic settings"

      echo "$(date '+%c') INFO:    Disable startup wizard"
      sed -i \
         -e "s%<IsStartupWizardCompleted>.*%<IsStartupWizardCompleted>true</IsStartupWizardCompleted>%" \
         "${config_dir}/config/system.xml"

      echo "$(date '+%c') INFO:    Configure transcode temporary directory to /media volume"
      sed -i \
         -e "s%<TranscodingTempPath>.*%<TranscodingTempPath>/media</TranscodingTempPath>%" \
         "${config_dir}/config/encoding.xml"

      echo "$(date '+%c') INFO:    Configure metadata directory to /metadata volume"
      sed -i \
         -e "s%<MetadataPath>.*%<MetadataPath>/metadata</MetadataPath>%" \
         "${config_dir}/config/system.xml"

      echo "$(date '+%c') INFO:    Enable remote access"
      sed -i \
            -e "s%<EnableRemoteAccess>.*%<EnableRemoteAccess>true</EnableRemoteAccess>%" \
            "${config_dir}/config/system.xml"

      echo "$(date '+%c') INFO:    Set web root"
      if [ "${jellyfin_web_root}" = "/" ]; then
         echo "$(date '+%c') INFO:    No base URL configured"
         sed -i \
            -e "s%<BaseUrl.*%<BaseUrl />%" \
            "${config_dir}/config/system.xml"
      else
         echo "$(date '+%c') INFO:    Configure base URL to: ${jellyfin_web_root}"
         sed -i \
            -e "s%<BaseUrl.*%<BaseUrl>${jellyfin_web_root}</BaseUrl>%" \
            "${config_dir}/config/system.xml"
      fi

      echo "$(date '+%c') INFO:    Remove empty network LAN address config"
      sed -i \
         -e "/\<LocalNetworkAddresses \/>/d" \
         "${config_dir}/config/system.xml"

      echo "$(date '+%c') INFO:    Remove empty network subnets config"
      sed -i \
         -e "/\<LocalNetworkAddresses \/>/d" \
         "${config_dir}/config/system.xml"

      if [ "$(grep -c "<LocalNetworkAddresses>" "${config_dir}/config/system.xml")" -eq 0 ]; then
         echo "$(date '+%c') INFO:    Create bind IP: ${lan_ip}"
         sed -i \
            -e "/<\/ServerConfiguration>/d" \
            "${config_dir}/config/system.xml"
         echo -e "  <LocalNetworkAddresses>\n    <string>${lan_ip}</string>\n  </LocalNetworkAddresses>\n</ServerConfiguration>" >> "${config_dir}/config/system.xml"
      elif [ "$(grep -c "<LocalNetworkAddresses>" "${config_dir}/config/system.xml")" -eq 1 ]; then
         echo "$(date '+%c') INFO:    Set bind IP: ${lan_ip}"
         sed -i \
            -e "/<LocalNetworkAddresses>/,/<\/LocalNetworkAddresses>/ s%<string>.*%<string>${lan_ip}<\/string>%" \
            "${config_dir}/config/system.xml"
      else
         echo "$(date '+%c') ERROR:   Invalid system.xml file. Multiple <LocalNetworkAddresses> entries detected"
         sleep 120
         exit 1
      fi

      if [ "$(grep -c "<LocalNetworkSubnets>" "${config_dir}/config/system.xml")" -eq 0 ]; then
         echo "$(date '+%c') INFO:    Configure local networks: ${docker_lan_ip_subnet}, ${host_lan_ip_subnet}"
         sed -i \
            -e "/<\/ServerConfiguration>/d" \
            "${config_dir}/config/system.xml"
         echo -e "  <LocalNetworkSubnets>\n    <string>${docker_lan_ip_subnet}</string>\n    <string>${host_lan_ip_subnet}</string>\n  </LocalNetworkSubnets>\n</ServerConfiguration>" >> "${config_dir}/config/system.xml"
      fi
      if [ "${jellyfin_enabled}" ]; then
         echo "$(date '+%c') INFO:    NGINX reverse proxy enabled"
         if [ "$(grep -c "<IsBehindProxy>" "${config_dir}/config/system.xml")" -eq 0 ]; then
            sed -i \
               -e "/<\/ServerConfiguration>/i \  <IsBehindProxy>false</IsBehindProxy>" \
               "${config_dir}/config/system.xml"
         elif [ "$(grep -c "<IsBehindProxy>" "${config_dir}/config/system.xml")" -eq 1 ]; then
            sed -i \
               -e "s%<IsBehindProxy>.*%<IsBehindProxy>false</IsBehindProxy>%" \
               "${config_dir}/config/system.xml"
         else
            echo "$(date '+%c') ERROR:   Invalid system.xml file. Multiple <IsBehindProxy> entries detected"
            sleep 120
            exit 1
         fi
         if [ "$(grep -c "<RequireHttps>" "${config_dir}/config/system.xml")" -eq 0 ]; then
            sed -i \
               -e "/<\/ServerConfiguration>/i \  <RequireHttps>true</RequireHttps>" \
               "${config_dir}/config/system.xml"
         elif [ "$(grep -c "<RequireHttps>" "${config_dir}/config/system.xml")" -eq 1 ]; then
            sed -i \
               -e "s%<RequireHttps>.*%<RequireHttps>true</RequireHttps>%" \
               "${config_dir}/config/system.xml"
         else
            echo "$(date '+%c') ERROR:   Invalid system.xml file. Multiple <RequireHttps> entries detected"
            sleep 120
            exit 1
         fi
      else
         echo "$(date '+%c') INFO:    Reverse proxy not enabled"
         sed -i \
            -e '/IsBehindProxy/d' \
            "${config_dir}/config/system.xml"
      fi
   fi
}

ConfigureAPIAccess(){
   echo "$(date '+%c') INFO:    Configure API access"
   local user_exists
   user_exists="$($(which sqlite3) "${config_dir}/data/authentication.db" "SELECT AppName FROM Tokens WHERE AppName=='stack_steve';")"
   if [ "${user_exists}" ]; then
      echo "$(date '+%c') INFO:    Set ${global_api_key} as access token for user: ${user_exists}"
      sqlite3 "${config_dir}/data/authentication.db" "UPDATE Tokens SET AccessToken='${global_api_key}' WHERE AppName=='${user_exists}';"
   else
      echo "$(date '+%c') INFO:    API Key access for stack_steve does not exist. Create new one"
      device_id="$(cat -v "${config_dir}/data/device.txt" | cut -d'?' -f2)"
      app_name="stack_steve"
      app_version="$(grep "var appVersion" /jellyfin/jellyfin-web/components/apphost.js | cut -d'"' -f2)"
      device_name="$(grep ServerName "${config_dir}/config/system.xml" | cut -d ">" -f 2 | cut -d "<" -f 1)"
      date_last_activity="0001-01-01 00:00:00Z"
      sqlite3 "${config_dir}/data/authentication.db" "INSERT INTO Tokens (AccessToken, DeviceId, AppName, AppVersion, DeviceName, IsActive, DateCreated, DateLastActivity) VALUES('${global_api_key}', '${device_id}', '${app_name}', '${app_version}', '${device_name}', '1', datetime('now'), '${date_last_activity}');"
   fi
}

LaunchJellyfin(){
   echo "$(date '+%c') INFO:    ***** Configuration of Jellyfin container launch environment complete *****"
   echo "$(date '+%c') INFO:    Handing over to Jellyfin's entrypoint"
   exec "/jellyfin/jellyfin" --datadir "/config" --cachedir "/cache" --ffmpeg "/usr/local/bin/ffmpeg"
}

##### Script #####
Initialise
CheckOpenVPNPIA
CreateGroup
CreateUser
SetOwnerAndGroup
Configure
ConfigureAPIAccess
LaunchJellyfin