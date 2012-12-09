#!/bin/bash
#this tool will upload a screenshot to the web
#if the first parameter is empty the default name will be
#the timestamp, and the image will be saved in png-format

#prefix for remote url
remote_uri="http://shots.ahta.nu/"

#default dir where the screenshot will be stored locally
local_dir="/home/ahluntang/shots/"

#ftp_server remote server and dir where screenshot will be uploaded
ftp_server="shots.ahta.nu/public_html"

#login for ftp
ftp_login=""

#password for ftp
ftp_pass=""

#if timestamp is on a timestamp will be added in the filename
timestamp=true
 
#checks if a command exists
checkCommand() {
which $1 >>/dev/null
if (($?!=0)) ; then
    echo "Error: command $1 doesn't exists, try 'sudo apt-get install $1'" 1>&2
    notify-send -i notification-network-ethernet-disconnected 'Screenshot uploader' "Error: command $1 doesn't exists, try 'sudo apt-get install $1'"
    exit 1
fi
}
 
#just checking if the required commands are present
checkCommand scrot
checkCommand lftp
checkCommand notify-send
checkCommand xclip
 
#set the filename depending on the config
if [ "$1" ] ; then
    if ${timestamp} ; then
        filename="$(date +%d%m%Y-%H%M%S-)$1"
    else
        filename="$1"
    fi
else
    filename="$(date +%d%m%Y-%H%M%S).png"
fi
 
#taking the screenshot
scrot -d 1 ${local_dir}${filename}
notify-send -i notification-network-ethernet-connected 'Screenshot uploader' "Screenshot taken, uploading screenshot now." 

#uploading the screenshot (arf, I used eval)
eval "lftp -e 'put ${local_dir}${filename} && exit' ${ftp_login}:${ftp_pass}@${ftp_server}"
echo ${remote_uri}${filename} | xclip -selection clipboard

#say something nice
echo "file ${local_dir}${filename} was put online"
notify-send -i notification-network-ethernet-connected 'Screenshot uploader' "file ${filename} was put online"
echo "Script completed"