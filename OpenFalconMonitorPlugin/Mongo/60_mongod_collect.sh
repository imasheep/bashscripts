#!/bin/bash

timestamp=$(date +%s)
endpoint=$HOSTNAME
step=60
dirname=$(cd $(dirname $0);pwd|awk -F\/ '$0=$NF')
bin_path="/home/service/falcon-agent/nagios/libexec"
base_path=$(cd $(dirname $0);pwd)
config_path=/home/service/mongodb-3.4.4
user="davdian"
pass="davdian"
host="127.0.0.1"
service="mongo"

metric_array=(mongo_asserts_regular:compute mongo_asserts_warning:compute mongo_asserts_msg:compute mongo_asserts_user:compute mongo_asserts_rollovers:compute mongo_connections_current:undefined mongo_connections_available:undefined mongo_connections_totalCreated:compute mongo_extra_info_page_faults:compute mongo_network_bytesIn:compute mongo_network_bytesOut:compute mongo_network_numRequests:compute mongo_opcounters_insert:compute mongo_opcounters_query:compute mongo_opcounters_update:compute mongo_opcounters_delete:compute mongo_opcounters_getmore:compute mongo_opcounters_command:compute mongo_mem_bits:undefined mongo_mem_resident:undefined mongo_mem_virtual:undefined mongo_metrics_cursor_timedOut:compute mongo_metrics_cursor_open_pinned:undefined mongo_metrics_cursor_open_total:undefined)

Get_current_value(){
	mongo_cmd="/home/service/mongodb-3.4.4/bin/mongo --host $host:$port --authenticationDatabase admin -u$user -p$pass"
	echo "db.serverStatus()"| $mongo_cmd |awk -v lev=0 '
		/{/{
			lev++
			key[lev]=gensub("\"","","g",$1)
			next
		}
		/}/{
			lev--
			next
		}
		{
			final_key=""
			for(i=2;i<=lev;i++){
				keystr=key[i]"_"
				final_key=final_key?final_key""keystr:keystr
			}
			final_key="mongo_"final_key""gensub("\"","","g",$1)
			match($NF,/[0-9]+(\.?[0-9]+)?/,a)
			printf a[0]!=""?final_key"="a[0]"\n":""
		}
	'
	eval $(echo "db.serverStatus()"| $mongo_cmd |awk -v lev=0 '
		/{/{
			lev++
			key[lev]=gensub("\"","","g",$1)
			next
		}
		/}/{
			lev--
			next
		}
		{
			final_key=""
			for(i=2;i<=lev;i++){
				keystr=key[i]"_"
				final_key=final_key?final_key""keystr:keystr
			}
			final_key="mongo_"final_key""gensub("\"","","g",$1)
			match($NF,/[0-9]+(\.?[0-9]+)?/,a)
			if(final_key~"UNKNOW")next
			printf a[0]!=""?final_key"="a[0]"\n":""
		}
	')

	echo "mongo_asserts_regular=$mongo_asserts_regular"
}

Curl_falcon(){
		
	for pre_metric in ${metric_array[@]};do
			[[ "$pre_metric" =~ ':compute' ]] \
				&& countertype="COUNTER" \
				|| countertype="GAUGE"
			metric="${pre_metric%%:*}"
			echo $metric
			value=$(eval echo \$$metric)
			data_unit='{"metric":"'$metric'","endpoint":"'$endpoint'","timestamp":'$timestamp',"step":'$step',"value":'$value',"counterType":"'$countertype'","tags":"'$tags'"}'
			[[ "$data_final" == "" ]] \
				&& data_final=$data_unit \
				|| data_final=$data_final,$data_unit
	done
	echo $data_final

	curl -s -X POST -d '['$data_final']' http://127.0.0.1:1988/v1/push

}
Test_port_status(){
    port_status=$($bin_path/check_tcp -H $host -p $port|awk -F'[ :]' '{print $2=="OK"?0:1}')
    dvd-falconpost -mport_status -e$endpoint -s$step -v$port_status -t"$tags,service=$service"
}
Post_mongo_status(){
	Get_current_value
	Curl_falcon
}

Main(){
	for file in $(find /home/service/mongodb* -maxdepth 2 -mindepth 2 -type f -name '*.conf');do
		port=$(awk '/port/{print $NF}' $file )
		tags="port=$port"
		Test_port_status
		[[ "$file" =~ mongos.conf$ ]] &&  Post_mongo_status
		
	done
    wait
}
Main &>/dev/null
