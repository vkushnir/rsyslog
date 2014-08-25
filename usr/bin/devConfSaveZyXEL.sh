#!/bin/sh
#
# devConfSaveZyXEL.sh - Save runing configs
# devConfSaveZyXEL.sh -i <ip> [-n <name>] [<text>]
#
###########################################################################

# Variables
# read variables from config file
. /etc/devConfVars.conf
# snmpCommunity="****"
# tftpRoot="****"
# tftpServer="****"
# dirRunning="****"
# dirStartup="****"
# logFile="****"
# diffOpt="-iubEB"
cfgMode="RUN"

Y=`date +%Y`
M=`date +%m`
D=`date +%d`
thisFN=`basename $0`

# SNMP ZyXEL
# System management
sysMgmt=12
# sysMgmt
Tftp=10
# sysMgmt.Tftp
ServerIp=1
RemoteFileName=2
ConfigIndex=3
Action=4
  ActionNone=0
  ActionBackupConfig=1
  ActionRestoreCconfig=2
  ActionMergeConfig=3
ActionStatus=5
  StatusNone=0
  StatusSuccess=1
  StatusFail=2
  StatusUnderAction=3

# Get Parameters

if [ $# -lt 1 ]; then
  echo "$thisFN: No options found! [$@]"
  exit 1
fi

devIP="noip"
while getopts "m:i:n:" opt; do
  case $opt in
    i) devIP=$OPTARG;;
    n) devNAME=$OPTARG;;
    m) cfgMode=${OPTARG^^};;
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

case $cfgMode in
  RUN)
    tftpDevRoot="${tftpRoot}/${dirRunning}/${Y}/${devID}/${Y}-${M}" ;;
  STU)
    tftpDevRoot="${tftpRoot}/${dirStartup}" ;;
    *)
    echo "$thisFN: Wrong mode [$cfgMode] !!!" >> $logFile
    exit 1 ;;
esac

# Generate file name
n=1
fn=$(printf "%s-%s%s%s_%02d.cfg" $devID $Y $M $D $n)
while [ -f ${tftpDevRoot}/${fn} ]; do
  echo "Check File: $fn"
  n=$(($n+1));
  fn=$(printf "%s-%s%s%s_%02d.cfg" $devID $Y $M $D $n)
done

# TFTP
sysObjectID=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP SNMPv2-MIB::sysObjectID.0)
if [ $? -ne 0 ]; then
  echo "$thisFN: IP: $devIP SNMP Error !!!" >> $logFile
  echo "" >> $logFile
  exit 1
fi

echo "$thisFN: CONFIG IP: $devIP, NAME: $devNAME, FileName: $fn, TEXT: $devLog" >> $logFile
echo "$thisFN: Location: ${tftpDevRoot}" >> $logFile

sysMgmtTftpServerIp="$sysObjectID.$sysMgmt.$Tftp.$ServerIp.0"
sysMgmtTftpRemoteFileName="$sysObjectID.$sysMgmt.$Tftp.$RemoteFileName.0"
sysMgmtTftpConfigIndex="$sysObjectID.$sysMgmt.$Tftp.$ConfigIndex.0"
sysMgmtTftpAction="$sysObjectID.$sysMgmt.$Tftp.$Action.0"
sysMgmtTftpActionStatus="$sysObjectID.$sysMgmt.$Tftp.$ActionStatus.0"

i=1
ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
while [ $ActionStatus = "under-action" -o $ActionStatus = $StatusUnderAction ]; do
  sleep 1s
  ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
  i=$(($i+1));
  if [ $i -gt 10 ]; then
    echo " Too long process! Exit."
    exit 1;
  fi
done

snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP $sysMgmtTftpServerIp a $tftpServer
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP $sysMgmtTftpRemoteFileName s $fn
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP $sysMgmtTftpAction i $ActionBackupConfig
sleep 1s

i=1
ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
while [ $ActionStatus = "under-action" -o $ActionStatus = $StatusUnderAction ]; do
  sleep 1s
  ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
  i=$(($i+1));
  if [ $i -gt $tftpWait ]; then
    echo " Too long process! Exit." >> $logFile
    echo "" >> $logFile
    exit 1;
  fi
done

# Store file
if [ $ActionStatus = success -o $ActionStatus = $StatusSuccess ]; then
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
    diffRes=`diff $diffOpt -qs --ignore-matching-lines='^;' ${tftpRoot}/${fn} ${tftpDevRoot}/${lf}`
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
    `diff $diffOpt --ignore-matching-lines='^;' ${tftpDevRoot}/${ff} ${tftpDevRoot}/${fn} > ${tftpDevRoot}/${devID}.diff`
  fi

else
  echo "$thisFN: Fail to save [$fn] from [$devIP] with status ($ActionStatus) !!!" >> $logFile
  echo "" >> $logFile
  exit 1
fi

