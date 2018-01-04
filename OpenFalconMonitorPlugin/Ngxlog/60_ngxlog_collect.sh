#!/bin/bash

base_path=$(cd $(dirname $0);pwd)
ngxlog_path="/data/logs/nginx_logs"
domain_flags="app mobile open service openapi gmouth analysis.bi heart.srv search seller smouth supplier y image.srv gateway.srv"
monitor_flags="app mobile open service gmouth search "
monitor_re=$(echo $monitor_flags|sed 's/ /|/g')
endpoint=$HOSTNAME
step=60
time_flag=$(date +%Y:%H:%M -d '-1 min')
log_flag=$(date +%Y%m%d -d '-1 min')
timestamp=$(date +%s)
tf="0_1,1_3,3_10,10_30,30u"
cf="2xx,3xx,4xx,5xx,xxx"
mf="ngx_req_time_cnt_,ngx_req_time_per_,ngx_ups_time_cnt_,ngx_ups_time_per_"
cof="ngx_http_code_cnt_,ngx_http_code_per_"

thread_file="/tmp/thread.pipe"
thread_num=5


Op_thread(){
    operation=$1
    case $operation in
        init)
            rm -rf $thread_file
            mkfifo $thread_file
            exec 9<>$thread_file
            for num in $(seq $thread_num);do
                echo " " 1>&9
            done
            ;;
        insert)
            echo " " 1>&9
            ;;
        delete)
            read -u 9
            ;;
        close)
            exec 9<&-
            ;;
    esac
}

Get_current_value(){
    for domain_flag in $domain_flags;do
		Op_thread delete
        {
            log_file=$ngxlog_path/$domain_flag.access.$log_flag.log
            eval $(tail -100000 $log_file | awk  -F[][] -vt_flags="$tf" -vc_flags="$cf" '
                    BEGIN{
                        split(t_flags,f,",")
                        split(c_flags,c,",")
                    } /'$time_flag'/{
						ip_cnt[$2]++
                        count++
                        $22<1?r_t[f[1]]++:$22<3?r_t[f[2]]++:$22<10?r_t[f[3]]++:$22<30?r_t[f[4]]++:r_t[f[5]]++
                        $24<1?u_t[f[1]]++:$24<3?u_t[f[2]]++:$24<10?u_t[f[3]]++:$24<30?u_t[f[4]]++:u_t[f[5]]++
                        $10<300?c_c[c[1]]++:$10<400?c_c[c[2]]++:$10<500?c_c[c[3]]++:$10<600?c_c[c[4]]++:c_c[c[5]]++
                    } END{
                        count=count?count:1
                        printf("ngx_req_cnt_total=%s\n",count)
                        for(i in f)printf("ngx_req_time_cnt_%s=%s\nngx_req_time_per_%s=%0.2f\n", f[i],r_t[f[i]]?r_t[f[i]]:0,f[i],sprintf("%.2f",r_t[f[i]]/count?r_t[f[i]]/count:0))
                        for(i in f)printf("ngx_ups_time_cnt_%s=%s\nngx_ups_time_per_%s=%0.2f\n", f[i],u_t[f[i]]?u_t[f[i]]:0,f[i],sprintf("%.2f",u_t[f[i]]/count?u_t[f[i]]/count:0))
                        for(i in c)printf("ngx_http_code_cnt_%s=%s\nngx_http_code_per_%s=%0.2f\n", c[i],c_c[c[i]]?c_c[c[i]]:0,c[i],sprintf("%.2f",c_c[c[i]]/count?c_c[c[i]]/count:0))
						printf("ngx_ip_cnt_max=%s\n",ip_cnt[asort(ip_cnt)]?ip_cnt[asort(ip_cnt)]:0)
                    }
            ')
            for metric in $(eval echo {$mf}{$tf}) $(eval echo {$cof}{$cf}) ngx_req_cnt_total ngx_ip_cnt_max;do
                [[ "$domain_flag" =~ ^($monitor_re)$ ]] \
                    && monitor_tag="flowmon_flag=on" \
                    || monitor_tag="flowmon_flag=off"
                tags="domain_flag=$domain_flag,$monitor_tag"
                value=$(eval echo \$$metric)
                countertype="GAUGE"
                data_unit='{"metric":"'$metric'","endpoint":"'$endpoint'","timestamp":'$timestamp',"step":'$step',"value":'$value',"counterType":"'$countertype'","tags":"'$tags'"}'
                [[ "$data_final" == "" ]] \
                    && data_final=$data_unit \
                    || data_final=$data_final,$data_unit
            done
			echo $data_final
            curl -s -X POST -d '['$data_final']' http://127.0.0.1:1988/v1/push
			Op_thread insert

        }&
    done
    wait
}
Main(){
	Op_thread init
    Get_current_value
}
Main &>/dev/null
