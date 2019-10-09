TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='swyft.conf'
CONFIGFOLDER='/root/.swyftcore'
COIN_DAEMON='swyftd'
COIN_CLI='swyft-cli'
COIN_PATH='/usr/local/bin/'
COIN_TGZ='https://github.com/swyft-project/swyft-core/releases/download/v2.0.1.1/swyft-2.0.1-x86_64-linux-gnu.tar.gz'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='SWYFT'
COIN_PORT=6518
RPC_PORT=5551
LATEST_VERSION=1000100

NODEIP=$(curl -s4 api.ipify.org)


RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


function update_node() {
  echo -e "Checking if ${RED}$COIN_NAME${NC} is already installed and running the lastest version."
  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service >/dev/null 2>&1
  apt -y install jq >/dev/null 2>&1
  VERSION=$($COIN_PATH$COIN_CLI getinfo 2>/dev/null| jq .version)
  if [[ "$VERSION" -eq "$LATEST_VERSION" ]]
  then
    echo -e "${RED}$COIN_NAME is already installed and running the lastest version.${NC}"
    exit 0
  elif [[ -z "$VERSION" ]]
  then
    echo "Continue with the normal installation"
  elif [[ "$VERSION" -ne "$LATEST_VERSION" ]]
  then
    systemctl stop $COIN_NAME.service >/dev/null 2>&1
    $COIN_PATH$COIN_CLI stop >/dev/null 2>&1
    sleep 10 >/dev/null 2>&1
    rm $COIN_PATH$COIN_DAEMON $COIN_PATH$COIN_CLI >/dev/null 2>&1
    rm -r $CONFIGFOLDER/{backups,blocks,budget.dat,chainstate,database,db.log,fee_estimates.dat,mncache.dat,mnpayments.dat,peers.dat,sporks,zerocoin} >/dev/null 2>&1
    download_node
    configure_systemd
    echo -e "${RED}$COIN_NAME updated to the latest version!${NC}"
    exit 0
  fi
}

function download_node() {
  echo -e "Prepare to download ${GREEN}$COIN_NAME${NC}."
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q $COIN_TGZ
  ls -l
  compile_error
  tar xvzf $COIN_ZIP --strip=2 >/dev/null 2>&1
  ls -l
  cp $COIN_DAEMON $COIN_CLI $COIN_PATH
  cd - >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}


function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
User=root
Group=root
Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid
ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=$RPC_PORT
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
staking=0
EOF
}

function create_key() {
  echo -e "Please go to the Debug Console in your${RED}$COIN_NAME${NC} wallet and type the following:"
  echo -e "[example: getnewaddress TPoS1]"
  echo
  echo -e "${GREEN}getnewaddress ALIAS${NC}"
  echo
  echo -e "This is the Merchant Address that you will give to the person on the other end of the contract."
  echo
  echo -e "Next you will type the following into the debug console (MERCHANT_ADDRESS is the address you just created):"
  echo
  echo -e "${GREEN}dumpprivkey MERCHANT_ADDRESS${NC}"
  echo
  echo -e "You will recieve a warning and an authorization code. Be sure to read and understand the warning and take note of the authorization code."
  echo
  echo -e "Next type the following (AUTH_CODE is the authorization code):"
  echo
  echo -e "${GREEN}dumpprivkey MERCHANT_ADDRESS AUTH_CODE${NC}"
  echo
  echo -e "That output string is your Merchantnode Private Key."
  echo
  echo -e "Copy that Merchantnode Private Key and paste it here:"
  echo -e "Enter your ${RED}$COIN_NAME Masternode Private Key${NC}:"
  read -e COINKEY
#   if [[ -z "$COINKEY" ]]; then
#     $COIN_PATH$COIN_DAEMON -daemon
#     sleep 30
#     if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
#       echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
#       exit 1
#     fi
#     COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
#     if [ "$?" -gt "0" ];
#       then
#       echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
#       sleep 30
#       COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
#     fi
#   $COIN_PATH$COIN_CLI stop
#   fi
# clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
maxconnections=256
bind=$NODEIP:$COIN_PORT
externalip=$NODEIP:$COIN_PORT
merchantnode=1
merchantnodeprivkey=$COINKEY
#Nodes
EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 api.ipify.org))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi
}

function prepare_system() {
echo -e "Preparing the system to install ${GREEN}$COIN_NAME${NC} merchantnode."
echo -e "This might take up to 15 minutes and the screen will not move, so please be patient."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev  libdb5.3++ unzip libzmq5 jq >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev libdb5.3++ unzip libzmq5 jq"
 exit 1
fi
clear
}

function important_information() {
 echo -e "================================================================================================================================"
 echo -e "$COIN_NAME Merchantnode is up and running listening on port ${RED}$COIN_PORT${NC}."
 echo -e "Configuration file is: ${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$COIN_PORT${NC}"
 echo -e "MERCHANTNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 echo -e "Please check ${RED}$COIN_NAME${NC} daemon is running with the following command: ${RED}systemctl status $COIN_NAME.service${NC}"
 echo -e "Use ${RED}$COIN_CLI masternode status${NC} to check your MN."
 if [[ -n $SENTINEL_REPO  ]]; then
  echo -e "${RED}Sentinel${NC} is installed in ${RED}$CONFIGFOLDER/sentinel${NC}"
  echo -e "Sentinel logs is: ${RED}$CONFIGFOLDER/sentinel.log${NC}"
 fi
 echo
 echo
 echo -e "The first half of the installation is complete.  When you find someone that wants to initiate a contract with you, you'll need"
 echo -e "to complete the second half of the installation. Instructions below."
 echo
 echo -e "When you find someone that wants a TPoS contract with you, send them the MERCHANT_ADDRESS from above. Once they have initiated"
 echo -e "the contract from THEIR local wallet, you need to make changes to your merchantnode.conf file in YOUR local wallet."
 echo -e "Add the following line into the merchantnode.conf file."
 echo
 echo -e "${GREEN}ALIAS $NODEIP:$COIN_PORT TXID"
 echo
 echo -e "Note that ALIAS is the alias of your Merchantnode and TXID is the transaction ID of the contract."
 echo -e "Type the following into the Debug Console of your local wallet to get the TXID:"
 echo
 echo -e "${GREEN}tposcontract list${NC}"
 echo
 echo -e "You will need to copy the TXID from that output and paste it into your merchantnode.conf file where it says TXID."
 echo -e "Then restart your local wallet."
 echo
 echo -e "You're almost there! Open your Debug Console and type:"
 echo
 echo -e "${GREEN}merchantnode start-alias ALIAS${NC}"
 echo
 echo -e "This should be the same alias that is in your merchantnode.conf file in local wallet. Hopefully the output says successful"
 echo -e "Next type:"
 echo
 echo -e "${GREEN}merchantnode list-conf${NC}"
 echo
 echo -e "The status should say PRE-ENABLED. It may take up to 30 minutes for it to change to ENABLED."
 echo -e "Once it switches to ENABLED, go back to your VPS and type one last thing at the prompt:"
 echo
 echo -e "${GREEN}swyft-cli setgenerate true 1 true TXID${NC}"
 echo
 echo -e "The TXID is the same TXID that you put into your merchantnode.conf file on your local wallet."
 echo
 echo -e "That's it!!!  Now just sit back and earn. To check if staking status is active, just type ${GREEN}swyft-cli getstakingstatus${NC}."
 echo -e "================================================================================================================================"
}

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  configure_systemd
}


##### Main #####
clear

checks
update_node
prepare_system
download_node
setup_node
