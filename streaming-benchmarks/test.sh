#!/bin/bash

HADOOP_VERSION=${HADOOP_VERSION:-"2.7.7"}
HADOOP_DIR="hadoop-$HADOOP_VERSION"

APACHE_MIRROR=$"https://archive.apache.org/dist"

fetch_untar_file() {
  local FILE="download-cache/$1"
  local URL=$2
  if [[ -e "$FILE" ]];
  then
    echo "Using cached File $FILE"
  else
        mkdir -p download-cache/
    WGET=`whereis wget`
    CURL=`whereis curl`
    if [ -n "$WGET" ];
    then
      wget -O "$FILE" "$URL"
    elif [ -n "$CURL" ];
    then
      curl -o "$FILE" "$URL"
    else
      echo "Please install curl or wget to continue.";
      exit 1
    fi
  fi
  tar -xzvf "$FILE"
}

HADOOP_FILE="$HADOOP_DIR.tar.gz"
fetch_untar_file "$HADOOP_FILE" "$APACHE_MIRROR/hadoop/core/$HADOOP_DIR/$HADOOP_FILE"

echo "$APACHE_MIRROR/hadoop/core/$HADOOP_DIR/$HADOOP_FILE"
