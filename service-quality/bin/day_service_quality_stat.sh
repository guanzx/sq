#!/bin/bash
#####################################################
#	Author:guanzx
#	Date:2014.08.29
#	Version:0.0.1
#	Descrption:该脚本用于临时数据支持，计算服务质量报告所需要的数据指标
#####################################################
usage="Usage: $0 [stat_date(yyyymmdd)]"
if [[ $# -eq 0 ]]
then
	stat_date=$(date -d "1 days ago" +%Y%m%d)
elif [[ $1 == [2-3][0-9][0-9][0-9][0-1][0-9][0-3][0-9] ]]
then
	stat_date=$1
	date_type=special
else
	echo "$usage"
	echo "Default stat_date is yesterday."
	exit 1
fi

# Change to base dir, this will make the script more robust
cd $(cd $(dirname $0)/..; pwd)
. etc/sq.conf

# 将日期格式转为yyyy/mm/dd的格式
format_stat_date=$(date -d "$stat_date" +%Y/%m/%d)

# 取数据并解压缩
function fetchDataAndUncompress {
	
	raw_data_dir=$1
	local_raw_data_dir=$2
	
	# 取数据
	[[ -d $local_raw_data_dir ]] && rm $local_raw_data_dir/*
	wget -r -l1 -np -nd -A $FILE_APPEND $raw_data_dir -P $local_raw_data_dir

	# 解压所有文件
	gzip -d ${local_raw_data_dir}/BeiJing*.gz
}

# 客户端启动日志的服务器路径
client_raw_data_dir=${CLIENT_START_PATH}/${format_stat_date}
# 抓取日志到本地的路径
local_client_raw_data_dir=${LOCAL_CLIENT_START_DIR}/${stat_date}

# 预下发素材日志的服务器路径
pre_mat_raw_dir=${PRE_MAT_PTAH}/${format_stat_date}
# 本地存放的路径
local_pre_mat_raw_dir=${LOCAL_PRE_MAT_DIR}/${stat_date}

# 配置文件的服务器路径
config_raw_dir=${CONFIG_PATH}/${format_stat_date}
# 本地存放的路径
local_config_raw_dir=${LOCAL_CONFIG_DIT}/${stat_date}

fetchDataAndUncompress $client_raw_data_dir $local_client_raw_data_dir
fetchDataAndUncompress $pre_mat_raw_dir $local_pre_mat_raw_dir
fetchDataAndUncompress $config_raw_dir $local_config_raw_dir
 
# 计算客户端总量
echo " Calc client start count..."
client_start_count=$(cat ${local_client_raw_data_dir}/BeiJing* | wc -l)

# 计算预下发素材列表失败数与成功数
echo " Calc pre_mat list count..."
preload_list_failure_count=$(awk -F'\t' '{if( $5 != 1 ) n++};END{ print n }' ${local_pre_mat_raw_dir}/BeiJing*)
preloat_list_success_count=$(awk -F'\t' '{if( $5 == 1 ) n++};END{ print n }' ${local_pre_mat_raw_dir}/BeiJing*)

# 计算预下发素材获取失败数与成功数
echo " Calc pre_mat get count..."
preload_get_success_count=$(awk -F'\t' '{ if($5==1 && $6==1) sum=sum+$7};END{print sum}' ${local_pre_mat_raw_dir}/BeiJing*)
preload_get_failure_count=$(awk -F'\t' '{if($5==1 && $6!=1) print $7}' ${local_pre_mat_raw_dir}/BeiJing* | awk -F',' '{sum=sum+NF};END{print sum}')

# 计算xml配置日志文件数
echo " Calc xml config count..."
ad_info_success_count=$(awk -F'\t' '{if( $5 == 1 ) n++};END{ print n }' ${local_config_raw_dir}/BeiJing*)
ad_info_failure_count=$(awk -F'\t' '{if( $5 != 1 ) n++};END{ print n }' ${local_config_raw_dir}/BeiJing*)

#---load data into database---
echo "load data into database"
sql="delete from stg_service_quality_d where log_date='$stat_date';"
echo $sql | mysql $CONN_STR_ARTEMIS_DB

sql="INSERT INTO stg_service_quality_d(client,list_success,list_failure,get_success,get_failure,info_success,info_failure,log_date)
VALUES(${client_start_count},${preloat_list_success_count},${preload_list_failure_count},${preload_get_success_count},${preload_get_failure_count}
,${ad_info_success_count},${ad_info_failure_count},${stat_date});"
echo $sql |mysql $CONN_STR_ARTEMIS_DB

# 删除前一天的数据
stat_date=$(date -d "$stat_date - 1 days " +%Y%m%d)
rm -rf local_client_raw_data_dir
rm -rf local_pre_mat_raw_dir
rm -rf local_config_raw_dir

echo "...Finish..."
