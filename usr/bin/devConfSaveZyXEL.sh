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
# maxSTU=n
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
    tftpDevRoot="${tftpRoot}/${dirRunning}/${Y}/${devID}/${Y}-${M}"
    pfn=$(printf "%s-%s%s%s" $devID $Y $M $D) ;;
  STU)
    tftpDevRoot="${tftpRoot}/${dirStartup}/${devID}" 
    pfn=$(printf "%s" $devID) ;;
    *)
    echo "$thisFN: Wrong mode [$cfgMode] !!!" >> $logFile
    exit 1 ;;
esac

gfn="${devID//./\\.}.*_[0-9]*\.cfg" 

# Generate file name
if [ -d $tftpDevRoot ]; then
  n=$(ls -1 --reverse $tftpDevRoot | grep $gfn | head -1 | cut -f2 -d_ | cut -f1 -d.)
  if [[ $n =~ ^[0-9]+$ ]]; then
    n=${n##0}
  else
    n=1
  fi
else
  n=1
fi
j=1
fn=$(printf "${pfn}_%02d.cfg" $n)
while [ -f ${tftpDevRoot}/${fn} ]; do
  echo "Check File: $fn"
  let n+=1
  let j+=1
  if [ $j -gt 199 ]; then
    echo "$thisFN: Error with filename generation !!!" >> $logFile
    echo "$thisFN: CONFIG IP: $devIP, NAME: $devNAME, FileName: $fn, TEXT: $devLog" >> $logFile
    echo "$thisFN: Location: ${tftpDevRoot}" >> $logFile
    echo "" >> $logFile
    exit 1
  fi
  if [ $n -gt 99 ]; then
    n=1
    ls --sort=time --reverse $tftpDevRoot | grep $gfn | head -1 | xargs -I {} -t rm -f $tftpDevRoot/{}
  fi
  fn=$(printf "${pfn}_%02d.cfg" $n)
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
  let i+=1
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
  let i+=1
  if [ $i -gt $tftpWait ]; then
    echo " Too long process! Exit." >> $logFile
    echo "" >> $logFile
    exit 1;
  fi
done

# Store file
if [ $ActionStatus = success -o $ActionStatus = $StatusSuccess ]; then
  if [ -d $tftpDevRoot ]; then
    flist=$(ls -1 --sort=time --reverse $tftpDevRoot | grep $gfn)
    fcnt=$(echo "$flist" | wc -l)
    if [ $fcnt -ge 1 ]; then
      if [ $cfgMode = STU -a $fcnt -ge $maxSTU ]; then
        let fs=fcnt-maxSTU
        ls --sort=time --reverse $tftpDevRoot | grep $gfn | head -$fs | xargs -I {} -t rm -f $tftpDevRoot/{}
        flist=$(ls -1 --sort=time --reverse $tftpDevRoot | grep $gfn)
      fi
      of=$(echo "$flist" | head -1)
      nf=$(echo "$flist" | tail -1)
    else
      of=0
      nf=0
    fi
  else
    fcnt=0
  fi
  if [ -f ${tftpDevRoot}/${of} ]; then
    diffRes=`diff $diffOpt -qs --ignore-matching-lines='^;' ${tftpRoot}/${fn} ${tftpDevRoot}/${nf}`
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
    `diff $diffOpt --ignore-matching-lines='^;' ${tftpDevRoot}/${of} ${tftpDevRoot}/${fn} > ${tftpDevRoot}/${devID}.diff`
  fi

else
  echo "$thisFN: Fail to save [$fn] from [$devIP] with status ($ActionStatus) !!!" >> $logFile
  echo "" >> $logFile
  exit 1
fi

