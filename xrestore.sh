#!/bin/bash
# Description: This script used to hot backup mysql data
# First Update: 2015-07-07
# Last Update: 2018-05-16
# Author: shaohy <shaohaiyang@gmail.com>
# Version: 0.3.0

BASE_DIR=$(dirname $0)
CONF_DIR=${BASE_DIR}/conf

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

if [ -z $1 ];then
     echo "Please give full backup directory"
     echo "Usage:$0 /usr/mysqldata/2018-05-18/full-2018-05-18-00-00"
     exit 1
fi

FULL_BACKUP_DIR=$1

restore_backup_data(){
    echo "setup 3: restore full data"
    printf "  %s %s \n" "restore" $FULL_BACKUP_DIR
    $XTRA_BACKUP_BIN --decompress --parallel=${CPU_CORE_NUM} $FULL_BACKUP_DIR > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e -n $GREEN "decompress ok," $COLOR_END
    else
        echo -e -n $RED "decompress error," $COLOR_END
        exit 1
    fi
    $XTRA_BACKUP_BIN --apply-log --redo-only --use-memory=512M $FULL_BACKUP_DIR > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e $GREEN "apply-log ok" $COLOR_END
    else
        echo -e $RED "apply-log error" $COLOR_END
        exit 1
    fi

    echo "setup 4: restore incremental data"
    INCREMENTAL_BACKUP_DIR=( $(ls -trd $FULL_BACKUP_DIR/../incremental*|grep -v .log) )
    for N in ${!INCREMENTAL_BACKUP_DIR[*]}; do
        INCRE_DIR=${INCREMENTAL_BACKUP_DIR[$N]}

	tail -1 $INCRE_DIR.log |grep -w "completed OK"
	if [ $? = 0 ];then
		echo -e $GREEN
	        printf "  %d/%s\t%s %s \n" $N ${#INCREMENTAL_BACKUP_DIR[*]} "restore" $INCRE_DIR
	else
		echo -e $RED
        	printf "  %d/%s\t%s %s \n" $N ${#INCREMENTAL_BACKUP_DIR[*]} "restore" $INCRE_DIR
		continue
	fi

        $XTRA_BACKUP_BIN --decompress --parallel=${CPU_CORE_NUM} $INCRE_DIR > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e -n $GREEN "decompress ok," $COLOR_END
        else
            echo -e -n $RED "decompress error," $COLOR_END
            exit 1
        fi

        $XTRA_BACKUP_BIN --apply-log --redo-only --use-memory=512M --incremental-dir=$LOCAL_RESOTRE_DIR/${RESTORE_DATE}/$INCRE_DIR $FULL_BACKUP_DIR > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e $GREEN "apply-log ok" $COLOR_END
        else
            echo -e $RED "apply-log error" $COLOR_END
            exit 1
        fi
    done

    echo "setup 5: copy back mysql data"
    $XTRA_BACKUP_BIN --copy-back $FULL_BACKUP_DIR > /dev/null 2>&1

    echo "setup 6: check mysqlbinlog and import"
    echo "cat $FULL_BACKUP_DIR/xtrabackup_binlog_info"
    echo "mysqlbinlog --start-position=xxx mysql-bin.00000x > ./all.sql"
    echo "mysql>SET SQL_LOG_BIN=0"
    echo "mysql>source all.sql"
    echo "mysql>SET SQL_LOG_BIN=1"
    echo -e $COLOR_END
}

restore_backup_data
