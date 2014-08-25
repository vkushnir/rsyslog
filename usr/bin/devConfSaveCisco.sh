#!/bin/sh
#
# devConfSaveCisco.sh - Save runing configs
# devConfSaveCisco.sh -i <ip> [-n <name>] [<text>]
#
###########################################################################

# Variables
# read variables from config file
. /etc/devConfVars.conf
# snmpCommunity="****"
# tftpRoot="****"
# tftpServer="****"
# tftpWait="****"
# dirRunning="****"
# dirStartup="****"
# logFile="****"
# diffOpt="-iubEB"

Y=`date +%Y`
M=`date +%m`
D=`date +%d`
thisFN=`basename $0`

# SNMP CISCO
# ConfigCopyProtocol
tftp=1; ftp=2; rcp=3; scp=4; sftp=5
# ConfigFileType
networkFile=1; iosFile=2; startupConfig=3; runningConfig=4; terminal=5; fabricStartupConfig=6
# ConfigCopyState
waiting=1; running=2; successful=3; failed=4
# RowStatus
active=1; notInService=2; notReady=3; createAndGo=4; createAndWait=5; destroy=6
# Get Parameters

if [ $# -lt 1 ]; then
  echo "$thisFN: No options found! [$@]"
  exit 1
fi

devIP="noip"
while getopts "i:n:" opt; do
  case $opt in
    i) devIP=$OPTARG;;
    n) devNAME=$OPTARG;;
    l) devLOG=$OPTARG;;
    *) echo "$thisFN: Specify IP address" >> $logFile; exit 1;;
  esac
done
shift $((OPTIND-1))
devLog=$@

if [ $devIP == "noip" ]; then
  echo "$thisFN: Specify IP address" >> $logFile
  echo "Specify IP address"
  exit 1
fi

r=$RANDOM
saveIFS=$IFS
IFS='.'
devID=$(printf "%03d.%03d.%03d.%03d" $devIP)
IFS=$saveIFS

#devID="${devIP}"
#if [ "$devNAME" != "" -a "$devNAME" != "$devIP" ]; then
#  devID="${devIP}-${devNAME}"
#fi

tftpDevRoot="${tftpRoot}/${dirRunning}/${Y}/${devID}/${Y}-${M}"

# Generate file name
n=1
fn=$(printf "%s-%s%s%s_%02d.cfg" $devID $Y $M $D $n)
while [ -f ${tftpDevRoot}/${fn} ]; do
  echo "Check File: $fn"
  n=$(($n+1));
  fn=$(printf "%s-%s%s%s_%02d.cfg" $devID $Y $M $D $n)
done

echo "$thisFN: CONFIG IP: $devIP, NAME: $devNAME, FileName: $fn, TEXT: $devLog" >> $logFile
echo "$thisFN: Location: ${tftpDevRoot}" >> $logFile
# r=1
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$r i $tftp >> $logFile
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$r i $runningConfig
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$r i $networkFile
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$r a $tftpServer
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyFileName.$r s $fn >> $logFile
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$r i $active
sleep 1s

i=1
ccCopyState=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r)
while [ "$ccCopyState" = "active" -o "$ccCopyState" = "running" ]; do
  sleep 1s
  ccCopyState=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyState.$r)
  i=$(($i+1));
  if [ $i -gt $tftpWait ]; then
    echo " Too long process! Exit." >> $logFile
    echo "" >> $logFile
    break
  fi
done
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$r i $destroy

# Store file
if [ $ccCopyState = "successful" ]; then
  if [ -d $tftpDevRoot ]; then
    flist=$(ls -1 --sort=time --reverse $tftpDevRoot | grep \.cfg)
    fcnt=$(echo $flist | wc -w)
    if [ $fcnt -ge 1 ]; then
      ff=$(echo $flist | tr ' ' '\n' | head -1)
      lf=$(echo $flist | tr ' ' '\n' | tail -1)
    else
      ff=0
      lf=0
    fi
  else
    fcnt=0
  fi
  if [ -f ${tftpDevRoot}/${lf} ]; then
    diffRes=`diff $diffOpt -qs --ignore-matching-lines='^!' ${tftpRoot}/${fn} ${tftpDevRoot}/${lf}`
    if [[ $diffRes == *identical ]]; then
      echo "$thisFN: New file same as previous." >> $logFile
      echo "" >> $logFile
      rm -f ${tftpRoot}/${fn}
      exit 0
    fi
  fi
  if [ ! -d $tftpDevRoot ]; then
    mkdir -p $tftpDevRoot
    chown -R tftpd:tftpd $tftpDevRoot
    chmod -R 755 $tftpDevRoot
  fi
  mv -f ${tftpRoot}/${fn} ${tftpDevRoot}/${fn}
  chmod 644 ${tftpDevRoot}/${fn}
  echo "" >> $logFile

  if [ $fcnt -ge 1 ]; then
    `diff $diffOpt --ignore-matching-lines='^!' ${tftpDevRoot}/${ff} ${tftpDevRoot}/${fn} > ${tftpDevRoot}/${devID}.diff`
  fi

else
  echo "$thisFN: Fail to save [$fn] from [$devIP] with status ($ActionStatus) !!!" >> $logFile
  echo "" >> $logFile
  exit 1
fi

