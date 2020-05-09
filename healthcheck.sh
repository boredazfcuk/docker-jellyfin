#!/bin/bash

if [ "$(netstat -plnt | grep -c 8096)" -ne 1 ]; then
   echo "Jellyfin HTTP port 8096 is not responding"
   exit 1
fi

echo "Jellyfin HTTP port 8096 responding OK"
exit 0