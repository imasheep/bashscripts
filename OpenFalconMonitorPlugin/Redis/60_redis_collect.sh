#!/bin/bash

timestamp=$(date +%s)
endpoint=$HOSTNAME
step=60
dirname=$(cd $(dirname $0);pwd|awk -F\/ '$0=$NF')
bin_path="/home/service/falcon-agent/nagios/libexec"
base_path=$(cd $(dirname $0);pwd)
service="redis"
host=127.0.0.1
metric_redis=(uptime_in_seconds:undefined rdb_bgsave_in_progress:undefined blocked_clients:undefined connected_clients:undefined connected_slaves:undefined expired_keys:compute keyspace_hits:compute keyspace_misses:compute total_commands_processed:compute used_memory:undefined used_memory_rss:undefined total_connections_received:compute)


Get_current_value(){
	metric_re=$(echo ${metric_redis[@]}|sed -r 's/:\w+//g;s/ /|/g')
	#redis-cli $auth -h $host -p $port "info"|awk -F: -vre="^$metric_re$" '$1~re{printf("redis_%s=\"%d\"\n",$1,$2)}'
	$r  "info"|awk -F: -vre="^$metric_re$" '$1~re{printf("redis_%s=\"%d\"\n",$1,$2)}'
	#eval  $(redis-cli $auth -h $host -p $port "info"|awk -F: -vre="^$metric_re$" '$1~re{printf("redis_%s=\"%d\"\n",$1,$2)}')
	eval  $($r  "info"|awk -F: -vre="^$metric_re$" '$1~re{printf("redis_%s=\"%d\"\n",$1,$2)}')
}

Get_current_conpercent(){
	#redis_max_con=$(redis-cli $auth -h $host -p $port config get maxclients|awk 'NR>1')
	redis_max_con=$($r  config get maxclients|awk 'NR>1')
	redis_cur_con=$redis_connected_clients
	redis_connected_percent=$(awk 'BEGIN{printf("%.2f\n", int("'$redis_max_con'")==0?'$redis_cur_con'/3000:'$redis_cur_con'/int("'$redis_max_con'"))}')
	falconpost -e$endpoint -mredis_connected_percent -v$redis_connected_percent -s$step -t"$tags"
}
Get_current_mempercent(){
	#redis_max_mem=$(redis-cli $auth -h $host -p $port config get maxmemory|awk 'NR>1')
	redis_max_mem=$($r config get maxmemory|awk 'NR>1')
	redis_cur_mem=$redis_used_memory
	redis_mem_percent=$(awk 'BEGIN{printf("%.2f\n", int("'$redis_max_mem'")==0?'$redis_cur_mem'/15000000000:'$redis_cur_mem'/int("'$redis_max_mem'"))}')
	falconpost -e$endpoint -mredis_mem_percent -v$redis_mem_percent -s$step -t"$tags"
}


Curl_falcon(){
		for pre_metric in ${metric_redis[@]};do
			[[ "$pre_metric" =~ ':compute' ]] \
				&& countertype="COUNTER" \
				|| countertype="GAUGE"
			metric="redis_${pre_metric%%:*}"
			value=$(eval echo \$$metric)
			[[ x"$value" == "x" ]] \
				&& continue
        	data_unit='{"metric":"'$metric'","endpoint":"'$endpoint'","timestamp":'$timestamp',"step":'$step',"value":'$value',"counterType":"'$countertype'","tags":"'$tags'"}'
        	[[ "$data_final" == "" ]] \
        	    && data_final=$data_unit \
        	    || data_final=$data_final,$data_unit
    done
    curl -s -X POST -d '['$data_final']' http://127.0.0.1:1988/v1/push
}

Test_max_connection(){
	#redis-cli $auth -h $host -p $port "quit" | egrep -iq "ERR max number" \
	$r  "quit" | egrep -iq "ERR max number" \
		&& falconpost -e$endpoint -mredis_connected_clients -s$step -v"-1" -t"$tags" \
        && exit
}
Test_port_status(){
    port_status=$($bin_path/check_tcp -H $host -p $port|awk -F'[ :]' '{print $2=="OK"?0:1}')
    falconpost -e$endpoint -mport_status -s$step -v$port_status -t"$tags"
    [[ "$port_status" == 1 ]] \
		&& continue
}

Main(){
	files=$(find /home/service/ -maxdepth 2 -mindepth 2 -name redis.conf) 
	files=$files" "$(find /etc/redis.conf.d/ -maxdepth 1 -mindepth 1 -name '*.conf')
	files=$files" "$(find /home/service/codis-*/conf -maxdepth 1 -mindepth 1 -name 'redis*.conf')
	for file in $files;do
		monitor_flag=$(awk -F: 'NR==1&&$0=$NF' $file)
		[[ "$monitor_flag" != on ]] && continue
		port=$(awk '$1=="port"{print $2}' $file)
		auth=$(awk -F'[ "]' '/^requirepass/{auth=$3}END{print auth?"-a "auth:auth}' $file)
		r="redis-cli $auth -h $host -p $port"
		[[ $port == "0" ]] \
			&& { 
				port=$(awk '$1=="unixsocket"&&$0=$2' $file)
				r="redis-cli -s $port -h $host $auth"
			}

		tags="port=$port"
		{
			Test_max_connection
			Test_port_status
			Get_current_value
			Get_current_conpercent
			Get_current_mempercent
			Curl_falcon
		} &
	done
    wait
}
Main   &>/dev/null
