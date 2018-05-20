#!/bin/bash
# Description: This script used to hot backup mysql data
# First Update: 2015-07-07
# Last Update: 2018-05-16
# Author: shaohy <shaohaiyang@gmail.com>
# Version: 0.3.0

BASE_DIR=$(dirname $0)
CONF_DIR=${BASE_DIR}/conf
TASK_LOCK=$CONF_DIR/is_need_backup

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
export BASE_DIR CONF_DIR CURRENT_DATETIME TODAY PATH
[ -e $TASK_LOCK ] || ( echo "You need to touch a \"is_need_backup\" file" ; exit 1 )

source $CONF_DIR/config
source $CONF_DIR/auth
if ! [ -e $XTRA_BACKUP_BIN ]; then
     echo "Please install percona-xtrabackup"
     exit 1
     if ! [ -e $QPRESS_BIN ]; then
       echo "Please install qpress"
       exit 1
     fi
fi

CURRENT_DATETIME=$(date +%Y-%m-%d-%H-%M-%S)
TODAY=${CURRENT_DATETIME:0:10}
HOUR=${CURRENT_DATETIME:11:2}
MIN=${CURRENT_DATETIME:14:2}
CHECK_POINTS="$LOCAL_DIR/${LOCAL_HOST[0]}/$TODAY/xtrabackup_checkpoints"
mkdir -p $LOCAL_DIR/${LOCAL_HOST[0]}/$TODAY/

innobackupex_backup(){
    $XTRA_BACKUP_BIN $XTRA_BACKUP_OPTIONS 2> ${LOCAL_BACKUP_DIR}.log

    if [ $? -ne 0 ]; then
	echo "[W]:MySQL_BACKUP Fail"
        exit 1
    fi

    TO_LSN=$(awk '{if($1 ~ "to_lsn") print $3}' $LOCAL_BACKUP_DIR/xtrabackup_checkpoints)
    if [[ ${TO_LSN} ]]; then
        echo ${TO_LSN} > $CHECK_POINTS
    else
	echo "[W]:No LSN Found"
        exit 1
    fi
}

full_backup(){
    BACKUP_TYPE="full"
    LOCAL_BACKUP_DIR="$LOCAL_DIR/${LOCAL_HOST[0]}/$TODAY/${BACKUP_TYPE}-${CURRENT_DATETIME}"

    XTRA_BACKUP_OPTIONS="--parallel=${CPU_CORE_NUM} --compress --compress-threads=${CPU_CORE_NUM} --compress-chunk-size=64K --no-timestamp --slave-info --defaults-file=$DB_CONF --user=$DB_USER --password=$DB_PASSWD --socket=$DB_SOCKET $LOCAL_BACKUP_DIR"
    innobackupex_backup
}

incremental_backup(){
    if [ -e $CHECK_POINTS ] ;then
        TO_LSN=`cat $CHECK_POINTS`
    else
        full_backup
        exit 0
    fi

    BACKUP_TYPE="incremental"
    LOCAL_BACKUP_DIR="$LOCAL_DIR/${LOCAL_HOST[0]}/$TODAY/${BACKUP_TYPE}-${CURRENT_DATETIME}"

    if [ ! $TO_LSN ] ;then
        echo "[W]:Last LSN is not set!"
        exit 0
    fi

    XTRA_BACKUP_OPTIONS="--parallel=${CPU_CORE_NUM} --compress --compress-threads=${CPU_CORE_NUM} --compress-chunk-size=64K --no-timestamp --slave-info --defaults-file=$DB_CONF --user=$DB_USER --password=$DB_PASSWD --socket=$DB_SOCKET --incremental --incremental-lsn=$TO_LSN $LOCAL_BACKUP_DIR"
    innobackupex_backup
}

clear_history_data(){
    DELETE_DATE=$(date -d "${MAX_SAVE} days ago" +%Y-%m-%d)
    [ -d $LOCAL_DIR/${LOCAL_HOST[0]}/$DELETE_DATE ] && rm -rf $LOCAL_DIR/${LOCAL_HOST[0]}/$DELETE_DATE
}

check_backup_proc(){
   if ps aux|grep $XTRA_BACKUP_BIN |grep -v grep > /dev/null ;then
       exit 0
   fi
}

if [ $HOUR -eq "00" -a $MIN -eq "00" ]; then
	check_backup_proc
	full_backup
	clear_history_data
elif [ `expr $MIN % 30` = 0 ]; then
	check_backup_proc
	incremental_backup
fi
