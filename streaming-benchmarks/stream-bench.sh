#!/bin/bash
# Copyright 2015, Yahoo Inc.
# Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
set -o pipefail
set -o errtrace
set -o nounset
set -o errexit

LEIN=${LEIN:-lein}
MVN=${MVN:-mvn}
GIT=${GIT:-git}
MAKE=${MAKE:-make}

KAFKA_VERSION=${KAFKA_VERSION:-"0.8.2.1"}
REDIS_VERSION=${REDIS_VERSION:-"4.0.11"}
SCALA_BIN_VERSION=${SCALA_BIN_VERSION:-"2.11"}
SCALA_SUB_VERSION=${SCALA_SUB_VERSION:-"12"}
SPARK_VERSION=${SPARK_VERSION:-"2.3.1"}
HADOOP_VERSION=${HADOOP_VERSION:-"2.7.7"}

REDIS_DIR="redis-$REDIS_VERSION"
KAFKA_DIR="kafka_$SCALA_BIN_VERSION-$KAFKA_VERSION"
SPARK_DIR="spark-$SPARK_VERSION-bin-hadoop2.7"
HADOOP_DIR="hadoop-$HADOOP_VERSION"

#Get one of the closet apache mirrors
APACHE_MIRROR=$"https://archive.apache.org/dist"

IP_LIST_INNER=("10.178.0.22" "10.178.0.23" "10.178.0.24")
IP_LIST_OUTER=("34.64.192.22" "34.64.235.200" "34.64.79.251")

ZK_PORT="2181"
ZK_CONNECTIONS=""
for value in "${IP_LIST_INNER[@]}"; do
	ZK_CONNECTIONS="$value:$ZK_PORT,$ZK_CONNECTIONS"
	ZK_CONNECTIONS=${ZK_CONNECTIONS%,}
done
KAFKA_PORT="9092"
TOPIC=${TOPIC:-"ad-events"}
PARTITIONS=${PARTITIONS:-6}
REP_FACTOR=${REP_FACTOR:-3}
LOAD=${LOAD:-1000}
CONF_FILE=./conf/localConf.yaml
TEST_TIME=${TEST_TIME:-180}

pid_match() {
   local VAL=`ps -aef | grep "$1" | grep -v grep | awk '{print $2}'`
   echo $VAL
}

start_if_needed() {
  local match="$1"
  shift
  local name="$1"
  shift
  local sleep_time="$1"
  shift
  local PID=`pid_match "$match"`

  if [[ "$PID" -ne "" ]];
  then
    echo "$name is already running..."
  else
    "$@" &
    sleep $sleep_time
  fi
}

stop_if_needed() {
  local match="$1"
  local name="$2"
  local PID=`pid_match "$match"`
  if [[ "$PID" -ne "" ]];
  then
    kill "$PID"
    sleep 1
    local CHECK_AGAIN=`pid_match "$match"`
    if [[ "$CHECK_AGAIN" -ne "" ]];
    then
      kill -9 "$CHECK_AGAIN"
    fi
  else
    echo "No $name instance found to stop"
  fi
}

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

create_kafka_topic() {
    local count=`$KAFKA_DIR/bin/kafka-topics.sh --describe --zookeeper "$ZK_CONNECTIONS" --topic $TOPIC 2>/dev/null | grep -c $TOPIC`
    if [[ "$count" = "0" ]];
    then
        $KAFKA_DIR/bin/kafka-topics.sh --create --zookeeper "$ZK_CONNECTIONS" --replication-factor $REP_FACTOR --partitions $PARTITIONS --topic $TOPIC
    else
        echo "Kafka topic $TOPIC already exists"
    fi
}

run() {
  OPERATION=$1
  if [ "SETUP" = "$OPERATION" ];
  then
    $GIT clean -fd

    echo 'kafka.brokers:' > $CONF_FILE
    for value in "${IP_LIST_INNER[@]}"; do
	echo '    - "'$value'"' >> $CONF_FILE
    done
    echo >> $CONF_FILE
    echo 'zookeeper.servers:' >> $CONF_FILE
    for value in "${IP_LIST_INNER[@]}"; do
        echo '    - "'$value'"' >> $CONF_FILE
    done
    echo >> $CONF_FILE
    echo 'kafka.port: '$KAFKA_PORT >> $CONF_FILE
	echo 'zookeeper.port: '$ZK_PORT >> $CONF_FILE
	echo 'redis.host: "localhost"' >> $CONF_FILE
	echo 'kafka.topic: "'$TOPIC'"' >> $CONF_FILE
	echo 'kafka.partitions: '$PARTITIONS >> $CONF_FILE
	echo 'process.hosts: 1' >> $CONF_FILE
	echo 'process.cores: 4' >> $CONF_FILE
	#echo 'storm.workers: 1' >> $CONF_FILE
	#echo 'storm.ackers: 2' >> $CONF_FILE
	echo 'spark.batchtime: 2000' >> $CONF_FILE
	
    $MVN clean install -Dspark.version="$SPARK_VERSION" -Dkafka.version="$KAFKA_VERSION" -Dscala.binary.version="$SCALA_BIN_VERSION" -Dscala.version="$SCALA_BIN_VERSION.$SCALA_SUB_VERSION"

    #Fetch and build Redis
    REDIS_FILE="$REDIS_DIR.tar.gz"
    fetch_untar_file "$REDIS_FILE" "http://download.redis.io/releases/$REDIS_FILE"

    cd $REDIS_DIR
    $MAKE
    cd ..

    #Fetch Kafka
    KAFKA_FILE="$KAFKA_DIR.tgz"
    fetch_untar_file "$KAFKA_FILE" "$APACHE_MIRROR/kafka/$KAFKA_VERSION/$KAFKA_FILE"

    #Fetch Spark
    SPARK_FILE="$SPARK_DIR.tgz"
    fetch_untar_file "$SPARK_FILE" "$APACHE_MIRROR/spark/spark-$SPARK_VERSION/$SPARK_FILE"

    #Fetch Hadoop
    HADOOP_FILE="$HADOOP_DIR.tar.gz"
    fetch_untar_file "$HADOOP_FILE" "$APACHE_MIRROR/hadoop/core/$HADOOP_FILE"

  elif [ "START_ZK" = "$OPERATION" ];
  then
    for value in "${IP_LIST_INNER[@]}"; do
    	ssh jinhuijun@$value /home/jinhuijun/kafka/bin/zookeeper-server-start.sh /home/jinhuijun/kafka/config/zookeeper.properties &
	sleep 3
    done
  elif [ "STOP_ZK" = "$OPERATION" ];
  then
    for value in "${IP_LIST_INNER[@]}"; do
    	ssh jinhuijun@$value pkill -9 -ef QuorumPeerMain &
        sleep 3
    done
  elif [ "START_REDIS" = "$OPERATION" ];
  then
    start_if_needed redis-server Redis 1 "$REDIS_DIR/src/redis-server" "$REDIS_DIR/redis.conf"
    cd data
    $LEIN run -n --configPath ../conf/benchmarkConf.yaml
    cd ..
  elif [ "STOP_REDIS" = "$OPERATION" ];
  then
    stop_if_needed redis-server Redis
    rm -f dump.rdb
  elif [ "START_KAFKA" = "$OPERATION" ];
  then
    for value in "${IP_LIST_INNER[@]}"; do
    	ssh jinhuijun@$value /home/jinhuijun/kafka/bin/kafka-server-start.sh /home/jinhuijun/kafka/config/server.properties &
        sleep 3
    done
    create_kafka_topic
  elif [ "STOP_KAFKA" = "$OPERATION" ];
  then
    for value in "${IP_LIST_INNER[@]}"; do
    	ssh jinhuijun@$value pkill -9 -ef Kafka &
        sleep 3
    done
  elif [ "START_SPARK" = "$OPERATION" ];
  then
    /home/jinhuijun/streaming-benchmarks/hadoop-2.7.7/sbin/start-dfs.sh
    sleep 3
    /home/jinhuijun/streaming-benchmarks/hadoop-2.7.7/sbin/start-yarn.sh
    sleep 3
#    start_if_needed org.apache.spark.deploy.worker.Worker SparkSlave 5 $SPARK_DIR/sbin/start-slave.sh spark://localhost:7077
  elif [ "STOP_SPARK" = "$OPERATION" ];
  then
    /home/jinhuijun/streaming-benchmarks/hadoop-2.7.7/sbin/stop-all.sh
#    stop_if_needed org.apache.spark.deploy.master.Master Master
#    stop_if_needed org.apache.spark.deploy.worker.Worker SparkSlave
    sleep 3
  elif [ "START_LOAD" = "$OPERATION" ];
  then
    cd data
    start_if_needed leiningen.core.main "Load Generation" 1 $LEIN run -r -t $LOAD --configPath ../$CONF_FILE
    cd ..
  elif [ "STOP_LOAD" = "$OPERATION" ];
  then
    stop_if_needed leiningen.core.main "Load Generation"
    cd data
    $LEIN run -g --configPath ../$CONF_FILE || true
    cd ..
  elif [ "START_SPARK_PROCESSING" = "$OPERATION" ];
  then
    "$SPARK_DIR/bin/spark-submit" --master yarn --class spark.benchmark.KafkaRedisAdvertisingStream ./spark-benchmarks/target/spark-benchmarks-0.1.0.jar "$CONF_FILE" &
#    "$SPARK_DIR/bin/spark-submit" --master spark://localhost:7077 --class spark.benchmark.KafkaRedisAdvertisingStream ./spark-benchmarks/target/spark-benchmarks-0.1.0.jar "$CONF_FILE" &
    sleep 5
  elif [ "STOP_SPARK_PROCESSING" = "$OPERATION" ];
  then
    stop_if_needed spark.benchmark.KafkaRedisAdvertisingStream "Spark Client Process"
  elif [ "SPARK_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_SPARK"
    run "START_SPARK_PROCESSING"
    run "START_LOAD"
    sleep $TEST_TIME
    run "STOP_LOAD"
    run "STOP_SPARK_PROCESSING"
    run "STOP_SPARK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "STOP_ALL" = "$OPERATION" ];
  then
    run "STOP_LOAD"
    run "STOP_SPARK_PROCESSING"
    run "STOP_SPARK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  else
    if [ "HELP" != "$OPERATION" ];
    then
      echo "UNKOWN OPERATION '$OPERATION'"
      echo
    fi
    echo "Supported Operations:"
    echo "SETUP: download and setup dependencies for running a single node test"
    echo "START_ZK: run a single node ZooKeeper instance on local host in the background"
    echo "STOP_ZK: kill the ZooKeeper instance"
    echo "START_REDIS: run a redis instance in the background"
    echo "STOP_REDIS: kill the redis instance"
    echo "START_KAFKA: run kafka in the background"
    echo "STOP_KAFKA: kill kafka"
    echo "START_LOAD: run kafka load generation"
    echo "STOP_LOAD: kill kafka load generation"
    echo "START_SPARK: run spark processes"
    echo "STOP_SPARK: kill spark processes"
    echo 
    echo "START_SPARK_PROCESSING: run the spark test processing"
    echo "STOP_SPARK_PROCESSSING: kill the spark test processing"
    echo
    echo "SPARK_TEST: run spark test (assumes SETUP is done)"
    echo "STOP_ALL: stop everything"
    echo
    echo "HELP: print out this message"
    echo
    exit 1
  fi
}

if [ $# -lt 1 ];
then
  run "HELP"
else
  while [ $# -gt 0 ];
  do
    run "$1"
    shift
  done
fi
