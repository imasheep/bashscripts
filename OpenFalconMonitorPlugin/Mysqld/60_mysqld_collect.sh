#!/bin/bash

timestamp=$(date +%s)
endpoint=$HOSTNAME
step=60
dirname=$(cd $(dirname $0);pwd|awk -F\/ '$0=$NF')
bin_path="/home/service/falcon-agent/nagios/libexec"
base_path=$(cd $(dirname $0);pwd)
config_path=/data/mysql_trade/
user="falcon_mon"
pass="f4e0N39HYrr3lqnF"
host="127.0.0.1"
service="mysqld"

metric_arrays=(metric_global_status metric_global_variables)

metric_global_status=(Aborted_clients:compute Aborted_connects:compute Bytes_received:compute Bytes_sent:compute Com_lock_tables:compute Com_rollback:compute Com_delete:compute Com_insert:compute Com_insert_select:compute Com_load:compute Com_replace:compute Com_select:compute Com_update:compute Qcache_hits:compute Slow_queries:compute Threads_connected:undefined Threads_running:undefined Uptime:undefined Queries:compute)

metric_global_variables=(query_cache_size:undefined)

Get_current_value(){
    flag=$1
    case $flag in
        global_status)
            sql="show global status"
            eval $(mysql -u$user -p$pass -h$host -P$port -e "$sql" 2>/dev/null|awk '{printf("mysqld_%s=\"%s\"\n",$1,$2)}')
            ;;
        slave_status)
            sql="show slave status\G"
            eval $(mysql -u$user -p$pass -h$host -P$port -e "$sql" 2>/dev/null|awk -F'[: ]+' 'NF==3{v=$3~/^[0-9.]+$/?$3:-1;$0="mysqld_"$2"="v;print $0}')
            ;;
        global_variables)
            sql="show global variables"
            eval $(mysql -u$user -p$pass -h$host -P$port -e "$sql" 2>/dev/null|awk '{printf("mysqld_%s=\"%s\"\n",$1,$2)}')
            ;;
    esac
}
Curl_falcon(){
    for metric_array in ${metric_arrays[@]};do
        {
            for pre_metric in $(eval echo \${$metric_array[@]});do
                    [[ "$pre_metric" =~ ':compute' ]] \
                        && countertype="COUNTER" \
                        || countertype="GAUGE"
                    metric="mysqld_${pre_metric%%:*}"
                    value=$(eval echo \$$metric)
					[[ "$value" == "" ]] \
						&& value="-1"
					data_unit='{"metric":"'$metric'","endpoint":"'$endpoint'","timestamp":'$timestamp',"step":'$step',"value":'$value',"counterType":"'$countertype'","tags":"'$tags'"}'
        			[[ "$data_final" == "" ]] \
        			    && data_final=$data_unit \
        			    || data_final=$data_final,$data_unit
            done
			echo $data_final

			curl -s -X POST -d '['$data_final']' http://127.0.0.1:1988/v1/push

        } &
    done
}

Test_max_connection(){
     /usr/bin/mysql -u$user -p$pass -h$host -P$port -e 'quit' 2>&1 |grep -qi 'Too many connections'  \
		&& falconpost -e$endpoint -mmysqld_Threads_connected -s$step -v-1 -t"$tags" \
        && exit
}
Test_app_alive(){
	/usr/bin/mysqladmin -u$user -p$pass -h$host -P$port ping 2>/dev/null |grep -qi "mysqld is alive" \
		&& app_alive_status=0 \
		|| app_alive_status=1
    falconpost -mmysqld_alive -e$endpoint -s$step -v$app_alive_status -t"$tags"
}
Test_port_status(){
    port_status=$($bin_path/check_tcp -H $host -p $port|awk -F'[ :]' '{print $2=="OK"?0:1}')
    falconpost -mport_status -e$endpoint -s$step -v$port_status -t"$tags,service=mysqld"
}
Test_slave_status(){
    slave_status_flag=$(/usr/bin/mysql -u$user -p$pass -h$host -P$port -e "show slave status\G" 2>/dev/null |egrep -i "Slave_IO_Running|Slave_SQL_Running"|grep -i "yes"|grep -v "grep"|wc -l)
	[ "$slave_status_flag" -eq 2 ] \
		&& slave_status=0 \
		|| slave_status=1
	falconpost -e$endpoint -mmysqld_slavestatus -s$step -v$slave_status -t"$tags"
}
Test_slave_delay(){
	slave_delay=$(/usr/bin/mysql -u$user -p$pass -h$host -P$port -e "show slave status\G" 2>/dev/null |awk  '$0~"Seconds_Behind_Master"{print $NF=="NULL"?0:$NF}')
	falconpost -mmysqld_Seconds_Behind_Master -e$endpoint -s$step -v$slave_delay -t"$tags"
}
Get_slow_log_cnt(){
	time_date_flag=$(date +%Y%m%d -d '-1 min'|sed 's/^20//g')
	time_hms_flag=$(date +%H:%M -d '-1 min')
	mysql_slow_log=${file%/*}/slow.log
	slow_log_cnt=$(tail -10000 $mysql_slow_log |grep -P "# Time: *$time_date_flag  ?$time_hms_flag" |wc -l)
	falconpost -mmysqld_slow_log_cnt -e$endpoint -s $stemp -v$slow_log_cnt -t"$tags"
}
Main(){
	for file in $(find /data/ -maxdepth 2 -mindepth 2 -type f -name 'my*.cnf');do
		port=$(awk '/\[/{flag=0}/\[mysqld\]/{flag=1}flag&&$1=="port"&&$0=$NF' $file)
		role=$(awk -F: '/#role:/&&$0=$2' $file)
        monitor_flag=$(awk -F: 'NR==1&&$0=$NF' $file)
        [[ "$monitor_flag" != on ]] && continue
		tags="port=$port"
		Test_max_connection
		Test_port_status
		Test_app_alive
		Get_current_value global_status
		Get_current_value global_variables
		[[ "$role" == "slave" ]] \
			&& {
				Test_slave_status
				Get_current_value slave_status
				Test_slave_delay
			}
		Get_slow_log_cnt
		Curl_falcon
	done
    wait
}
Main &>/dev/null
