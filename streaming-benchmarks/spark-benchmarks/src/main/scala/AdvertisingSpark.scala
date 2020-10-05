/*
 * Copyright 2015, Yahoo Inc.
 * Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
 */

// scalastyle:off println

package spark.benchmark

import java.util
import java.util.HashSet

import org.apache.spark.streaming

import org.apache.spark.SparkConf
import org.json.JSONObject
import org.sedis._
import redis.clients.jedis._
import scala.collection.Iterator
import org.apache.spark.rdd.RDD
import benchmark.common.Utils
import scala.collection.JavaConverters._
import scala.collection.mutable.Buffer

import org.apache.spark.sql._
import org.apache.spark.sql.types._
import org.apache.spark.sql.functions.{from_json,col}
import org.apache.spark.sql.streaming.Trigger

object KafkaRedisAdvertisingStream {
  def main(args: Array[String]) {

    val commonConfig = Utils.findAndReadConfigFile(args(0), true).asInstanceOf[java.util.Map[String, Any]];

    val redisPost = commonConfig.get("redis.host") match {
      case s: String => s
      case other => throw new ClassCastException(other + " not a List[String]")
    }
    val redisHost = List("10.178.0.22","10.178.0.23","10.178.0.24")

    val kafkaHosts = commonConfig.get("kafka.brokers").asInstanceOf[java.util.List[String]] match {
      case l: java.util.List[String] => l.asScala.toSeq
      case other => throw new ClassCastException(other + " not a List[String]")
    }
    val kafkaPort = commonConfig.get("kafka.port") match {
      case n: Number => n.toString()
      case other => throw new ClassCastException(other + " not a Number")
    }

    val brokers = joinHosts(kafkaHosts, kafkaPort)

    val spark = SparkSession.builder.appName("KafkaReader").getOrCreate()
    val df = spark.readStream.format("kafka").option("kafka.bootstrap.servers",brokers).option("subscribe","ad-events").load()
    df.printSchema()

    import spark.implicits._
    val df2 = df.selectExpr("CAST(value AS STRING)")
    val struct = new StructType().add(StructField("user_id", StringType,false)).add(StructField("page_id", StringType,false))
    .add(StructField("ad_id", StringType,false)).add(StructField("ad_type", StringType,false)).add(StructField("event_type", StringType,false))
    .add(StructField("event_time", StringType,true)).add(StructField("ip_address", StringType,false))
    val events = df2.select(from_json($"value",struct).as("events"))
    events.printSchema()

    val df3 = events.select("events.ad_id","events.event_time","events.event_type")
    df3.printSchema()

    val query = df3.writeStream.foreach(
      new ForeachWriter[Row]{
          val jedisClusterNodes = new HashSet[HostAndPort]

          val hosts: List[String] = redisHosts
          hosts.foreach(host=> jedisClusterNodes.add(new HostAndPort(host,6379)))

          def connect() = {
              val jc: JedisCluster = new JedisCluster(jedisClusterNodes)
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
              jc.hset(campaign_window_pair,"event_type",event_type)
          }
          
          override def close(errorOrNull: Trhowalbe)={
          }
      }
    ).start()
    query.awaitTermination()

    val jedisClusterNodes = new HashSet[HostAndPort]
    redisHost.foreach(host=> jedisClusterNodes.add(new HostAndPort(host,6379)))
    val jc: JedisCluster = new JedisCluster(jedisClusterNodes)

    val query = df3.writeStream.outputMode("update").foreachBatch{(batchDF: DataFrame,batchId: Long)=>
    batchDF.foreachPartition(writeRedisTopLevel(_,jc))}.start()
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

  def writeRedisTopLevel(items: Iterator[org.apache.spark.sql.Row], jc: JedisCluster) {
    //val pool = new Pool(new JedisPool(new JedisPoolConfig(), redisHost, 6379, 2000))
    items.foreach(item => writeWindow(jc, item))
    jc.close()
  }

  private def writeWindow(jc: JedisCluster, item: org.apache.spark.sql.Row) : String = {
    val event_time = item(1).toString()
    val event_type = item(2).toString()
    jc.hset(event_time,"event_type",event_type)
    return "event_type"
  }
}
