#!/bin/bash

speed=$(sudo /usr/bin/dmidecode -t 17 | awk -F: '
/Configured Memory Speed/ && $2 !~ /Unknown|Not Configured/ {
    gsub(/^ +/,"",$2)
    print $2
    exit
}')

if [ -z "$speed" ]; then
    speed=$(sudo /usr/bin/dmidecode -t 17 | awk -F: '
    /Speed:/ && $2 !~ /Unknown|No Module Installed/ {
        gsub(/^ +/,"",$2)
        print $2
        exit
    }')
fi

echo "${speed:-N/A}"
