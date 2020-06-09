#!/bin/bash

#set -x

PRIVKEY=""
log="./install-`date "+%Y-%m-%d"`.log"
URL_32="https://github.com/TBC-Project/TongBaoCoin/releases/download/v1.0.2.0/tbc-1.0.2-i686-pc-linux-gnu.tar.gz"
URL_64="https://github.com/TBC-Project/TongBaoCoin/releases/download/v1.0.2.0/tbc-1.0.2-x86_64-linux-gnu.tar.gz"


CONFIGDIR="/root/.TongBaoCoin/"
BIN_PATH="/usr/local/tbc/"
UNAME=`which uname`
WHOAMI=`which whoami`
NETSTAT=`which netstat`
LSOF=`which lsof`
WGET=`which wget`
CURL=`which curl`
UFW=`which ufw`
SED=`which sed`
TAR=`which tar`
UPDATEINIT=`which update-rc.d`
INITSER="tbcd-ser"

#for upgrade check!
GZ_SIZE=
URL=
TBC_SIZE=

NODEIP=""
PORT=62222
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;34m'
NC='\033[0m'

# the basic command 
#cp, mv, mkdir, head, read, echo, ps, grep, which 

SUDO=""
function check_user()
{
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi    
}

function check_command()
{
   if [ "$LSOF" == "" -o "$NETSTAT" == "" -o "$WGET" == "" -o "$CURL" == "" -o "$SED" == "" \
        -o "$TAR" == "" -o "$UPDATEINIT" == "" -o "$UFW" == "" ]; then
      echo "INSTALL required deb package, please wait ..."
      
      DEBIAN_FRONTEND=noninteractive apt-get -y update >>$log 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
             curl lsof wget sed tar net-tools ufw sysv-rc >>$log 2>&1
      if [ "$?" != "0" ]; then
         echo -e "${RED} Some packages were not install properly. Please execute the following commands: ${NC}" 
         echo "apt-get update"
         echo "apt-get install curl lsof wget sed tar net-tools ufw sysv-rc"
         exit 1
      fi

      # check again 
      LSOF=`which lsof`
      NETSTAT=`which netstat`
      if [ "$LSOF" == "" -a "$NETSTAT" == ""  ]; then
         echo -e "${RED}Failed to find 'lsof' and 'netstat', please execute the following command: ${NC}"
         echo "apt-get install lsof net-tools"
         exit 1
      fi
      WGET=`which wget`
      CURL=`which curl`
      if [ "$WGET" == "" -a "$CURL" == "" ]; then
         echo -e "${RED}Failed to find 'wget' and 'curl',  please execute the following command: ${NC}"
         echo "apt-get install wget curl"
         exit 1
      fi
      TAR=`which tar`
      if [ "$TAR" == "" ]; then
         echo -e "${RED}Failed to find 'tar', please execute the following command: ${NC}"
         echo "apt-get install tar"
         exit 1
      fi
      UFW=`which ufw`
      if [ "$UFW" == "" ]; then
         echo -e "${RED}Failed to find 'ufw', please execute the following command: ${NC}"
         echo "apt-get install ufw"
         exit 1
      fi
      UPDATEINIT=`which update-rc.d`
      if [ "$UPDATEINIT" == "" ]; then
         echo -e "${RED}Failed to find 'update-rc.d', please execute the following command: ${NC}"
         echo "apt-get install sysv-rc"
         exit 1
      fi
   fi
}

function set_firewall() {
    echo -e "setting up firewall to allow ingress on port ${GREEN}$PORT${NC}"
    ufw allow ${PORT}/tcp >/dev/null 2>&1 
    ufw allow ssh >/dev/null 2>&1
    ufw limit ssh/tcp >/dev/null 2>&1   
    ufw default allow outgoing >/dev/null 2>&1
    echo "y" | ufw enable >/dev/null 2>&1
}

function stop_server()
{ 
    echo "Stopping tbcd masternode with tbc-cli, please waiting ..." 
    for i in `seq 1 10`
    do
	if ps ax | grep -v "grep" |  grep -q "tbcd " ; then
            if [ -f $BIN_PATH/bin/tbc-cli ] && [ -f ${CONFIGDIR}/tbc.conf ]; then
                echo -e "${GREEN} Try to stop ${i}... ${NC}"
                ${BIN_PATH}/bin/tbc-cli -datadir=${CONFIGDIR} stop >/dev/null 2>&1
                sleep 4
            fi
        else
           break
        fi
    done
 
    ## if not stopped, use kill -9
    if ps ax | grep -v "grep" |  grep -q "tbcd " ; then 
        echo -e "${RED} FAILED to stop TBCD MN with tbc-cli. ${NC}"
        echo "Please stop it By yourself !"
        exit -1
    fi
}

function start_server()
{
   if [ -f ${BIN_PATH}/bin/tbcd ]; then
      ps ax | grep "tbcd " | grep -v "grep" > /dev/null
      if [ "$?" == "0" ]; then
          echo -e "${GREEN}tbcd masternode has alread started. ${NC} "
          exit 0
      else
          echo "Start server ...."
          set_firewall
          ${BIN_PATH}/bin/tbcd -datadir=${CONFIGDIR} -debug --daemon
          dis_info
          exit 0
      fi
   else
     echo -e "${RED}tbcd masternode is NOT fully installed, please try to run $0 again! ${NC}"
     exit 1;
   fi
}

function check_v64_v32()
{
    osVer="64"
    if [ $UNAME == "" ]; then
        read -p " Please input the OS version. Input 64 if it is x86_64(or amd64), input 32 if it is i686: " osVer
        if [ "$osVer" != "64" -a "$osVer" != 32 ]; then
            read -p "Please input '64' or '32': " osVer
            if [ "$osVer" != "64" -a "$osVer" != 32 ]; then
               echo "Faild to set OS version, exit this process!"
               exit 1
            fi
        fi
    else
        $UNAME -a | grep -q "x86"
        if [ "$?" != "0" ]; then
           osVer="32"
        fi
    fi

    if [ "$osVer" == "64" ]; then
        URL=${URL_64}
        GZ_SIZE=35936306
        TBC_SIZE=10166816
    else
        URL=${URL_32}
        GZ_SIZE=37157531
        TBC_SIZE=10737816
    fi
}

function check_upgrade()
{
    if [ -f ${CONFIGDIR}/tbc.conf ] && [ -f "$BIN_PATH"/bin/tbcd ]; then
        FILESIZE=`ls -l "$BIN_PATH"/bin/tbcd | awk -F' ' '{print $5}'`
        if [ "$FILESIZE" != "$TBC_SIZE"  ]; then
            echo "There is new version of TBC, upgrade will NOT overwrite config, but upgrade and restart the daemon."
            echo -n -e "If you want to set upgrade, please Enter ${RED}Y${NC} or ${RED}y${NC}"
            read -p ": " wantUpgrade
            if [ "$wantUpgrade" == "y" -o "$wantUpgrade" == "Y" ]; then
                stop_server
                download_bin_tgt
                start_server
            fi
        fi  
    fi
}


function check_start()
{
    echo "Checking the MN server ..."
    if [ "$LSOF" != "" ]; then
       $SUDO $LSOF -i :${PORT} >/dev/null
    else
       $SUDO $NETSTAT -ln | grep -q "${PORT}"
    fi

    if [ "$?" == "0" ]; then
        echo "tbc masternode has started. "
        echo -n -e "If you want to restart server, please enter ${RED}Y${NC} or ${RED}y${NC}"
        read -p ": " wantRestart
        if [ "$wantRestart" == "y" -o "$wantRestart" == "Y" ]; then
            stop_server
            start_server
        else
            echo -e "${GREEN}Exit this script process!${NC}"
        fi
        exit 1
    fi

    if [ -f ${CONFIGDIR}/tbc.conf ] && [ -f "$BIN_PATH"/bin/tbcd ]; then
        echo -e "This machine has config file, and new config will ${RED}OVERWRITE${NR} old config."
        echo -n -e "If you want to set new config, please Enter ${RED}Y${NC} or ${RED}y${NC}"
        read -p ": " wantNewConfig
        if [ "$wantNewConfig" == "Y" -o "$wantNewConfig" == "y" ]; then
            echo ""
        else
            start_server
        fi
    fi
}

function check_param()
{
    if [ "${PRIVKEY}" == "" ]; then
        echo ""
        read -p " Please input masternode privkey: " PRIVKEY 
    fi
    keyLen=`expr length "$PRIVKEY"` 
    if [ $keyLen -lt 20 ]; then
        echo -e "${RED}Error, length of PriveKey Should be bigger than 20.${NC}"
        echo -e "If you want to input masternode privkey again, please enter ${RED}Y${NC} or ${RED}y${NC}"
        read -p ": " wantAgain
        if [ "$wantAgain" == "Y" -o "$wantAgain" == "y" ]; then
            PRIVKEY=""
            check_param
        else
            echo -e "${RED}Exit this script process!${NC}"
            exit 1
        fi
    fi 
}

function set_ip()
{
    declare -a ALLIPS
    for ip in $(ifconfig -s | grep -v -E "^lo |^Iface |^Kernel " | awk '{print $1}')
    do
        ALLIPS+=($(curl --interface $ip --connect-timeout 2 -s4 ident.me))
    done

    if [ ${#ALLIPS[@]} -gt 1 ]; then
        INDEX=0
        for ip in "${ALLIPS[@]}"
        do
            INDEX=`echo "${INDEX} + 1" | bc `
            echo ${INDEX} $ip
        done
        echo -e "${GREEN}More ips. Please type 1 to use the 1th IP, 2 for the 2th Ip, and so on...${NC} "
        read -e ": " choose
        choose=`echo "${choose} - 1" |bc`
        NODEIP=${ALLIPS[$choose]}
    elif [ ${#ALLIPS[@]} -eq 1 ] ; then
        NODEIP=${ALLIPS[0]}
    else
        echo -e "${RED}Error to get the IP, please make sure the server can access the InterNet. ${NC}"
        exit 1
    fi
}

function set_config() 
{
    rpcuser="npcrpc"
    rpcpasswd=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48`
    echo "username:" $rpcuser
    echo "password:" $rpcpasswd

    $SUDO mkdir -p ${CONFIGDIR} 2>/dev/null
    
npc_config_str="
rpcuser=RPCUSERNAME
rpcpassword=RPCUSERPASSWORD

rpcallowip=127.0.0.1
listen=1
server=1
daemon=1

logtimestamps=1
maxconnections=256
masternode=1

externalip=MASTERNODEIP
bind=0.0.0.0:MASTERNODEPORT
masternodeaddr=MASTERNODEIP
masternodeprivkey=MASTERNODEKEY
"
    echo "set config file ..."
    if [ "$SED" != "" ]; then
        $SUDO echo "${npc_config_str}" | \
              $SED -e "s/MASTERNODEIP/${NODEIP}/g" | \
              $SED -e "s/MASTERNODEPORT/${PORT}/g" | \
              $SED -e "s/RPCUSERNAME/${rpcuser}/g" | \
              $SED -e "s/RPCUSERPASSWORD/${rpcpasswd}/g" | \
              $SED -e "s/MASTERNODEKEY/${PRIVKEY}/g"  >tbc.conf 2>/dev/null
    else
    echo "" > tbc.conf
        echo "rpcuser=${rpcuser}" >> tbc.conf
        echo "rpcpassword=${rpcpasswd}" >> tbc.conf
        echo "" >> tbc.conf
        echo "rpcallowip=127.0.0.1" >> tbc.conf
        echo "listen=1" >> tbc.conf
        echo "server=1" >> tbc.conf
        echo "daemon=1" >> tbc.conf
        echo "logtimestamps=1" >> tbc.conf
        echo "maxconnections=256" >> tbc.conf
        echo "masternode=1" >> tbc.conf
        echo "" >> tbc.conf
        echo "externalip=${NODEIP}" >> tbc.conf
        echo "bind=0.0.0.0:${PORT}" >> tbc.conf
        echo "masternodeaddr=${localip}" >> tbc.conf
        echo "masternodeprivkey=${PRIVKEY}" >> tbc.conf
    fi
   $SUDO cp tbc.conf ${CONFIGDIR}/ 2>/dev/null
}

function download_bin_tgt()
{
    echo -e "${GREEN}Downloading the package files, please wait ...${NC}"
    if [ "$WGET" != "" ]; then
       $SUDO $WGET --tries 3 ${URL} -O CK-tbcd.tar.gz
    elif [ "$CURL" != "" ];then
       $SUDO $CURL ${URL} -o CK-tbcd.tar.gz --progress
    fi

    if [ "$?" != "0"  ]; then
        echo -e "${RED}FAILED to download server file, please try later. ${NC}"
        exit 1
    fi

    SERSIZE=`ls -l CK-tbcd.tar.gz | awk -F' ' '{print $5}'`
    if [ "${SERSIZE}" == "${GZ_SIZE}" ]; then
        echo "uncompress package .."
           $SUDO $TAR zxf CK-tbcd.tar.gz >>$log 2>&1
        ## delete, not bak old files!
        $SUDO rm -rf "$BIN_PATH" >>$log 2>&1
        $SUDO mkdir -p "$BIN_PATH" >>$log 2>&1
        $SUDO mv tbc-1.0.2/* "$BIN_PATH"
    else
       echo -e "${RED}download package size not right. Please RE-install again. ${NC}"
       exit 1
    fi

}


function add_sysinit_ser()
{
cat << EOF > /etc/init.d/${INITSER}
#!/bin/bash  
### BEGIN INIT INFO  
#  
# Provides:  tbcd_MN_server  
# Short-Description:    initscript  
# Description:  This file should be used to construct scripts to be placed in /etc/init.d.  
#               used to start tbcd masternode server when os start!
#  
### END INIT INFO  
  
## Fill in name of program here. 
CONFIGDIR="/root/.TongBaoCoin"
PROG_SER="/usr/local/tbc/bin/tbcd"
PROG_CLI="/usr/local/tbc/bin/tbc-cli"
UFW=\`which ufw\`  

status() {
    ps ax | grep "tbcd " | grep -v "grep" > /dev/null
    if [ "\$?" == "0" ]; then
        echo "* tbcd masternode is running"
        exit 0
    else
        echo "* tbcd masternode is not running"
        exit 0
    fi 
}

start() {
    if [ -f "\$PROG_SER" ]; then
        ps ax | grep "tbcd " | grep -v "grep" > /dev/null
        if [ "\$?" == "0" ]; then
            echo "tbcd is currently running started"
            exit 0
        else
            echo "Start server ...."
            if [ "\$UFW" != "" ]; then
                \$UFW allow 62222/tcp
            fi
            \$PROG_SER -datadir=\${CONFIGDIR} --daemon
            exit 0
        fi
    else
        echo "Not found server, please try to run install again!"
    fi
}  
  
stop() { 
    ps ax | grep "tbcd " | grep -v "grep" > /dev/null
    if [ "\$?" == "0" ]; then
        if [ -f "\$PROG_CLI" ] && [ -f "\${CONFIGDIR}/tbc.conf" ]; then
            "\$PROG_CLI" -datadir=\${CONFIGDIR} stop
        echo "Stopping TBCD MasterNode ..."
            sleep 2
        else
            pid=\`ps ax | grep -v "grep" | grep -i "tbcd " | grep -o "^[0-9]*" | head -n 1\`
            kill -9 \$pid
        fi
        echo "TBCD MasterNode Stoped!"
    else
        echo "TBCD MasterNode not started!" 1>&2  
    fi

}  
  
## Check to see if we are running as root first.  
if [ "\$(id -u)" != "0" ]; then  
    echo "This script must be run as root" 1>&2  
    exit 1  
fi  
  
case "\$1" in  
    start)  
        start  
        exit 0  
    ;;  
    stop)  
        stop  
        exit 0  
    ;;  
    reload|restart|force-reload)  
        stop  
        start  
        exit 0
    ;; 
    status)
        status
        exit 0         
    ;;  
    **)  
        echo "Usage: \$0 {start|stop|reload|status}" 1>&2  
        exit 1  
    ;;  
esac  
EOF

    $SUDO chmod +x /etc/init.d/${INITSER}
    UPDATEINIT=`which update-rc.d`
    if [ "$UPDATEINIT" != "" ]; then
       $SUDO $UPDATEINIT ${INITSER} defaults 95 > /dev/null 2>&1
    fi
}

function dis_info()
{
    echo "==============================================================================================="
    echo "TBC Masternode is installed."
    echo ""
    echo "tbcd daemon Usage:"
    echo -e "Start: ${RED}/etc/init.d/${INITSER} start ${NC}"
    echo -e "Stop: ${RED}/etc/init.d/${INITSER} stop ${NC}"
    echo -e "Restart: ${RED}/etc/init.d/${INITSER} restart ${NC}"
    echo -e "Status: ${RED}/etc/init.d/${INITSER} status ${NC}"
    echo "tbcd masternode Usage"
    echo -e "Status: ${RED}${BIN_PATH}/bin/tbc-cli masternode status${NC}"
    echo ""
    echo "Basic informations:"
    echo -e "Configuration files are in: ${RED}${CONFIGDIR}${NC}"
    echo -e "Executable files are in: ${RED}${BIN_PATH}${NC}"
    echo -e "VPS_IP:PORT ${RED}$NODEIP:${PORT}${NC}"
    echo -e "MASTERNODE PRIVATEKEY is: ${RED}$PRIVKEY${NC}"
    echo ""
    echo "==============================================================================================="
}



function main()
{
    PRIVKEY=$1

    check_user
    check_command
    add_sysinit_ser
    check_v64_v32
    check_upgrade   #exit if upgrade
    
    check_start
    download_bin_tgt

    check_param
    set_ip
    set_config
    start_server
}

main $@


