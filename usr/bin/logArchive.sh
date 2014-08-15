#!/bin/sh
#
# logArchive.sh - Archive device logs
#
###########################################################################

# Variables
LOG_ROOT="/var/log/devices"
ARCH_ROOT="/var/archive/log"

CDATE=`date +%Y-%m-%d`

# Archive logs older than two month

echo "Current Date: $CDATE"
# Loop through previous month
for month in {12..2}; do
  Y=`date +%Y -d "$CDATE -${month} month"`
  M=`date +%m -d "$CDATE -${month} month"`
  
  LOG="${LOG_ROOT}/${Y}/${Y}-${M}"
  if [ -d $LOG ]; then
    # Get devices list
    DEVICES=`find ${LOG} -type f -printf "%f\n" | cut -d"_" -f1 | sort | uniq`
    # Loop through IP list
    for IP in $DEVICES
    do
      # Get files for archive
      DLIST=`find ${LOG} -name "${IP}_*" -type f -print | sort`
      ARCH="${ARCH_ROOT}/${Y}/${IP}"
      AFN="${ARCH}/${IP}_${Y}-${M}.zip"	
      mkdir -p $ARCH
      if [ -f $AFN ]; then
        zip -uj9 $AFN $DLIST
      else
        zip -j9 $AFN $DLIST
      fi
    done
    # Delete old logs
    if [ $month -gt 6 ]; then
      echo "DELETE $LOG"
      rm -rf $LOG 
    fi
  fi
done

