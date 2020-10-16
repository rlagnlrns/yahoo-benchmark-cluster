/*
 * Copyright 2015, Yahoo Inc.
 * Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
 */

// scalastyle:off println

package spark.benchmark

import java.util
import java.util.HashSet

import org.apache.spark.streaming

import org.json.JSONObject
import org.sedis._
import redis.clients.jedis._
import scala.collection.Iterator
import benchmark.common.Utils
import scala.collection.JavaConverters._
import scala.collection.mutable.Buffer

import org.apache.spark.sql._
import org.apache.spark.sql.types._
import org.apache.spark.sql.functions.{from_json,col}

object KafkaRedisAdvertisingStream {
  def main(args: Array[String]) {

    val commonConfig = Utils.findAndReadConfigFile(args(0), true).asInstanceOf[java.util.Map[String, Any]];

    val redisHosts = commonConfig.get("redis.hosts").asInstanceOf[java.util.List[String]] match {
      case l: java.util.List[String] => l.asScala.toSeq
      case other => throw new ClassCastException(other + " not a List[String]")
    }
    val kafkaHosts = commonConfig.get("kafka.brokers").asInstanceOf[java.util.List[String]] match {
      case l: java.util.List[String] => l.asScala.toSeq
      case other => throw new ClassCastException(other + " not a List[String]")
    }
    val kafkaPort = commonConfig.get("kafka.port") match {
      case n: Number => n.toString()
      case other => throw new ClassCastException(other + " not a Number")
    }

    val brokers = joinHosts(kafkaHosts, kafkaPort)

    val spark = SparkSession.builder.appName("KafkaRedisAdvertisingStream").getOrCreate()
    val rawDataFromKafka = spark.readStream.format("kafka").option("kafka.bootstrap.servers",brokers).option("subscribe","ad-events").load()

    import spark.implicits._
    val dataFromKafka = rawDataFromKafka.selectExpr("CAST(value AS STRING)")
    val struct = new StructType().add(StructField("user_id", StringType,false)).add(StructField("page_id", StringType,false))
    .add(StructField("ad_id", StringType,false)).add(StructField("ad_type", StringType,false)).add(StructField("event_type", StringType,false))
    .add(StructField("event_time", StringType,true)).add(StructField("ip_address", StringType,false))
    val events = dataFromKafka.select(from_json($"value",struct).as("events"))

    val filteredData = events.select("events.ad_id","events.event_time","events.event_type").filter("events.event_type == 'view'")

    val query = filteredData.writeStream.foreach(
      new ForeachWriter[Row]{
          val jedisClusterNodes = new HashSet[HostAndPort]

          val hosts: Seq[String] = redisHosts
          hosts.foreach(host=> jedisClusterNodes.add(new HostAndPort(host,6379)))

	  var jc: JedisCluster = _

          def connect() = {
              jc = new JedisCluster(jedisClusterNodes)
          }

          override def open(partitionId: Long, version: Long): Boolean = {
              return true
          }

          override def process(record: Row) = {
              val event_time = record(1).toString()
              val event_type = record(2).toString()
              if (jc == null){
                  connect()
              }
              jc.hset(event_time,"event_type",event_type)
          }
          
          override def close(errorOrNull: Throwable)={
	      jc.close()
          }
      }
    ).start()
    query.awaitTermination()
  }

  def joinHosts(hosts: Seq[String], port: String): String = {
    val joined = new StringBuilder();
    
    hosts.foreach({
      host =>
      if (!joined.isEmpty) {
        joined.append(",");
      }

      joined.append(host).append(":").append(port);
    })
    return joined.toString();
  }
}
