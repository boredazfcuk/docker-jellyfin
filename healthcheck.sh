#!/bin/bash

if [ "$(netstat -plnt | grep -c 8096)" -ne 1 ]; then
   echo "Jellyfin HTTP port 8096 is not responding"
   exit 1
fi

if [ "$(hostname -i 2>/dev/null | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | wc -l)" -eq 0 ]; then
   echo "NIC missing"
   exit 1
fi

echo "Jellyfin HTTP port 8096 responding OK"
exit 0