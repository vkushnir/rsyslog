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
devID="${devIP}"

if [ "$devNAME" != "" -a "$devNAME" != "$devIP" ]; then
  devID="${devIP}-${devNAME}"
fi

case $cfgMode in
  RUN)
    tftpDevRoot="${tftpRoot}/${dirRunning}/${Y}/${devIP}/${Y}-${M}/${Y}-${M}-${D}" ;;
  STU)
    tftpDevRoot="${tftpRoot}/${dirStartup}" ;;
    *)
    echo "$thisFN: Wrong mode [$cfgMode] !!!" >> $logFile
    exit 1 ;;
esac

n=1
fn="${devID}_${n}.cfg"
while [ -f ${tftpDevRoot}/${fn} ]; do
  echo "Check File: $fn"
  n=$(($n+1));
  fn="${devID}_${n}.cfg";
done

echo "$thisFN: CONFIG IP: $devIP, NAME: $devNAME, FileName: $fn, TEXT: $devLog" >> $logFile
echo "$thisFN: Location: ${tftpDevRoot}" >> $logFile

# TFTP
sysObjectID=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP SNMPv2-MIB::sysObjectID.0)

sysMgmtTftpServerIp="$sysObjectID.$sysMgmt.$Tftp.$ServerIp.0"
sysMgmtTftpRemoteFileName="$sysObjectID.$sysMgmt.$Tftp.$RemoteFileName.0"
sysMgmtTftpConfigIndex="$sysObjectID.$sysMgmt.$Tftp.$ConfigIndex.0"
sysMgmtTftpAction="$sysObjectID.$sysMgmt.$Tftp.$Action.0"
sysMgmtTftpActionStatus="$sysObjectID.$sysMgmt.$Tftp.$ActionStatus.0"

n=1
ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
while [ $ActionStatus = "under-action" -o $ActionStatus = $StatusUnderAction ]; do
  sleep 1s
  ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
  n=$(($n+1));
  if [ $n -gt 10 ]; then
    echo " Too long process! Exit."
    exit 1;
  fi
done

snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP $sysMgmtTftpServerIp a $tftpServer
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP $sysMgmtTftpRemoteFileName s $fn
snmpset -v 2c -O qv -t 5 -c $snmpCommunity $devIP $sysMgmtTftpAction i $ActionBackupConfig
sleep 1s

ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
while [ $ActionStatus = "under-action" -o $ActionStatus = $StatusUnderAction ]; do
  sleep 1s
  ActionStatus=$(snmpget -Oqv -v 2c -m ALL -c $snmpCommunity $devIP $sysMgmtTftpActionStatus)
  n=$(($n+1));
  if [ $n -gt 10 ]; then
    echo " Too long process! Exit."
    exit 1;
  fi
done

# TYPE: one of i, u, t, a, o, s, x, d, b, n
#        i: INTEGER, u: unsigned INTEGER, t: TIMETICKS, a: IPADDRESS
#        o: OBJID, s: STRING, x: HEX STRING, d: DECIMAL STRING, b: BITS
#        U: unsigned int64, I: signed int64, F: float, D: double

#Set date folder
if [ $ActionStatus = success -o $ActionStatus = $StatusSuccess ]; then
  mkdir -p $tftpDevRoot
  chown -R tftpd:tftpd $tftpDevRoot
  mv -f ${tftpRoot}/$fn ${tftpDevRoot}/${fn} >> $logFile
  echo "" >> $logFile
else
  if [ $ActionStatus = fail -o $ActionStatus = $StatusFail ]; then 
    echo "$thisFN: Fail to save [$fn] from [$devIP] !!!" >> $logFile
    echo "" >> $logFile
  fi
fi



