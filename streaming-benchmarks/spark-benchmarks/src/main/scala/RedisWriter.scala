import org.apache.spark.sql.ForeachWriter
import org.apache.spark.sql.Row
import redis.clients.jedis.jedis
import redis.clients.jedis.HostAndPort

import java.util.HashSet

class RedisForeachWriter(redisHosts: List[String]) extends
ForeachWriter[Row]{
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