#!/bin/bash

timestamp=$(date +%s)
endpoint=$HOSTNAME
step=$(echo $0|grep -Po '\d+(?=_)')
dirname=$(cd $(dirname $0);pwd|awk -F\/ '$0=$NF')
bin_path="/home/service/falcon-agent/nagios/libexec"
host="127.0.0.1"
service="php-fpm"
fpm_config="/home/service/php/etc/pool.d/www.conf"
fpm_log="/data/logs/php_logs/www-fpm.php.log"
fpm_slow_log="/data/logs/php_logs/www-fpm.slow.log"
time_flag="$(date +%d-%b-%Y" "%H:%M -d '-1 min')"
time_flag_slow="$( date +%b" "%d" "%H:%M -d '-1 min')"
time_7flag_slow="$(date +%d-%b-%Y" "%H:%M -d '-1 min')"
metric_fpm=(idle_processes:undefined active_processes:undefined total_processes:undefined)


Get_current_value(){
	eval $(env SCRIPT_NAME=/phpfpmstatus SCRIPT_FILENAME=/phpfpmstatus QUERY_STRING= REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:$port| awk '{match($0,/([^:]+): +([0-9]+)/,a);printf a[1]a[2]?"phpfpm_"gensub(" ","_","g",a[1])"="a[2]"\n":""}')
}
Curl_falcon(){
	for pre_metric in ${metric_fpm[@]};do
			[[ "$pre_metric" =~ ':compute' ]] \
				&& countertype="COUNTER" \
				|| countertype="GAUGE"
			metric="phpfpm_${pre_metric%%:*}"
			value=$(eval echo \$$metric)
			data_unit='{"metric":"'$metric'","endpoint":"'$endpoint'","timestamp":'$timestamp',"step":'$step',"value":'$value',"counterType":"'$countertype'","tags":"'$tags'"}'
			[[ "$data_final" == "" ]] \
				&& data_final=$data_unit \
				|| data_final=$data_final,$data_unit
        done
		curl -s -X POST -d '['$data_final']' http://127.0.0.1:1988/v1/push
	wait


}
Test_port_status(){
    port_status=$($bin_path/check_tcp -H 127.0.0.1 -p $port|awk -F'[ :]' '{print $2=="OK"?0:1}')
    falconpost -mport_status -s$step -v$port_status -t"$tags,service=php-fpm"
    [[ "$port_status" == 1 ]] \
        && continue
}
Get_process_percent(){
	max_process=$(awk '$1=="pm.max_children"&&$0=$3' $file)
	processnum_per=$(awk 'BEGIN{printf("%0.2f",'$phpfpm_active_processes'/'$max_process')}')
	falconpost -mphpfpm_processnum_per -s$step -v$processnum_per -t"$tags"
}
Log_check(){
	eval $(tail -10000 $fpm_log|awk -F'[ :]' '/'"$time_flag"'/{a[$6]++}END{for(i in a)print i"_cnt="int(a[i])}')
	eval $(tail -10000 $fpm_slow_log|awk '/'"$time_flag_slow"'|'"$time_7flag_slow"'/{cnt++}END{print "Slow_cnt="int(cnt)}')
	falconpost -mphplog_warn_cnt  -v${Warning_cnt:-0}
	falconpost -mphplog_fatal_cnt  -v${Fatal_cnt:-0}
	falconpost -mphplog_slow_cnt  -v${Slow_cnt:-0}
}

Main(){
	for file in $(find /home/service/php*/etc/pool.d  -type f -name *.conf);do
		port=$(awk -F'[: ]+' '/listen/&&$0=$NF' $file)
		tags="port=$port"
	#	{
		Get_current_value
		Get_process_percent
		Test_port_status
		Log_check
		Curl_falcon
	#	} &
	done
	[ -f /home/service/php7/lib/ini.d/yaf_conf.ini ] \
		&& {
			env_flag=$(cat /home/service/php7/lib/ini.d/yaf_conf.ini |awk -F= '$1=="yaf.environ"&&$0=$2')
			echo $env_flag
			for file in $(find /home/work/psrv_*/conf/$env_flag  -type f -name 'swoole.ini');do 
				port=$(cat $file|awk -F= '$1=="port"&&$0=$2')
				tags="port=$port"
				Test_port_status
			done
		}
	
}
Main &>/dev/null
