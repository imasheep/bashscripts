#!/bin/bash

timestamp=$(date +%s)
endpoint=$HOSTNAME
step=60
dirname=$(cd $(dirname $0);pwd|awk -F\/ '$0=$NF')
bin_path="/home/service/falcon-agent/nagios/libexec"
base_path=$(cd $(dirname $0);pwd)
config_path="/home/service"
monitor_port=3600
counter_re="client_eof|client_err|request_bytes|requests|response_bytes|responses|server_eof|server_err|server_timedout|server_ejected_at|forward_error|fragments|server_ejects"
gauge_re="client_connections|in_queue|in_queue_bytes|out_queue|out_queue_bytes|server_connections|curr_connections|uptime"



Test_port_status(){
    port_status=$($bin_path/check_tcp -H $host -p $port|awk -F'[ :]' '{print $2=="OK"?0:1}')
    falconpost -e$endpoint -mport_status -s$step -v$port_status -t"$pre_tags,service=twemproxy"
    [[ "$port_status" == 1 ]] \
                && continue
}

Curl_falcon(){
	count=0
	datas=$(nc $host $monitor_port|python -m json.tool|awk -F: '/{/{tag_flag++;tag_flag==3?tag="r_flag="gensub("[ \"]","","g",$1):1}/}/{tag_flag--;tag=""}$NF~/^ ?[0-9.]+,? *$/{printf "twpxy_"gensub("[\" ]","","g",$1)" "gensub("[ ,|\"]","","g",$2)" ";print tag_flag==3?tag:""}')
	data_count=$(echo "$datas"|wc -l)
	echo "$datas"|while read metric value tag;do
		let count++
		[[ "$metric" =~ $counter_re ]] \
			&& countertype="COUNTER" \
			|| countertype="GAUGE"
		[[ "$tag" == "" ]] \
			&& tags=$pre_tags \
			|| tags=$pre_tags,$tag
		data_unit='{"metric":"'$metric'","endpoint":"'$endpoint'","timestamp":'$timestamp',"step":'$step',"value":'$value',"counterType":"'$countertype'","tags":"'$tags'"}'
		[[ "$data_final" == "" ]] \
        	    && data_final=$data_unit \
        	    || data_final=$data_final,$data_unit

		[ $count -eq "$data_count" ] \
			&& {
				curl -s -X POST -d '['$data_final']' http://127.0.0.1:1988/v1/push
			}
	done


}

Main(){
    for file in $(find $config_path -maxdepth 2 -mindepth 2 -name 'nutcracker.yml');do

		host=$(awk -F: 'gsub(" ","",$2)&&/listen/&&$0=$2' $file)
		port=$(awk -F: '/listen/&&$0=$NF' $file)
		pre_tags="port=$port"
		auth=$(awk -F: '/redis_auth/{print substr($NF,2)}' $file)
		{
			Test_port_status
			Curl_falcon
		}&

    done
    wait
}
Main &>/dev/null
