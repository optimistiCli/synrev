#!/bin/bash

# Remotely start synergy client on a mac
# Usage: rem-sync.sh [-c <config>] [-p <port>] [-U <remote username>]

DEFAULT_CONFIG="$HOME/.synergy.conf"
DEFAULT_PORT='24800'

#####################
### REMOTE SCRIPT ###
###     START     ###
#####################

read -d '' REMORE_SCRIPT << 'END_OF_REMOTE_SCRIPT'
#!/bin/bash

# Usage: synergy-client-start.sh <server ip> [<server port>]

SERVER_IP='@IP@'
SERVER_PORT='@PORT@'

if [ -z "$SERVER_IP" ] ; then
	echo 'Error: no server IP'
	exit 1
fi

echo "$SERVER_IP" | grep -q '^[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}$'
if [ $? -ne 0 ] ; then 
	SERVER_DNS=$(host "$SERVER_IP")
	if [ $? -ne 0 ] ; then
		echo "Error: Server $SERVER_IP not found"
		exit 1
	fi
	SERVER_IP=$(echo "$SERVER_DNS" | grep -o '[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}')
fi

# TODO: Test me
if [ -n "$SERVER_PORT" ] ; then
	echo "$SERVER_PORT" | grep -q '^[[:digit:]]\\+$'
	if [ $? -ne 0 ] ; then 
		echo "Error: Bad port number $SERVER_PORT"
		exit 1
	fi
else 
	SERVER_PORT='24800'
fi

echo Connecting to "$SERVER_IP":"$SERVER_PORT"

if uname | grep -qi '\\<darwin\\>' ; then
	PATH=/Applications/Synergy.app/Contents/MacOS:"$HOME"/Applications/Synergy.app/Contents/MacOS:"$PATH"
fi

SYNERGYC_PATH=$(which synergyc)

if [ $? -ne 0 ] ; then
	echo 'Error: Can not find synergyc binary'
	exit 1
fi

SYN_DIR="${SYNERGYC_PATH%/[^/]*}"

while IFS= read -r PS_LINE ; do
	PS_LINE_ARRAY=($PS_LINE)
	SYN_PID="${PS_LINE_ARRAY[1]}"
	SYN_BIN="${PS_LINE_ARRAY[10]}"

	echo kill "$SYN_PID"

	if [ $? -ne 0 ] ; then
		echo "Error: Can not kill old process $SYN_PID: $SYN_BIN"
		exit 1
	fi

	sleep 1
done < <(ps uax | grep -i "$SYN_DIR"/synergy | grep -v grep)

echo synergyc -f --no-tray --debug FATAL --name "$HOSTNAME" --enable-drag-drop --enable-crypto "$SERVER_IP":"$SERVER_PORT" & disown 

END_OF_REMOTE_SCRIPT

#####################
### REMOTE SCRIPT ###
###      END      ###
#####################


# Decide on config file and port

while getopts ":c:p:u:" opt ; do
	case $opt in
		c)
			CONFIG="$OPTARG"
			;;
		p)
			PORT="$OPTARG"
			;;
		u)
			REMOTE_USER="$OPTARG"
			;;
	esac
done

if [ -z "$CONFIG" ] ; then
	CONFIG="$DEFAULT_CONFIG"
fi

if [ ! -f "$CONFIG" ] ; then
	echo "Error: config file not found $CONFIG"
	exit 1
fi

if [ -z "$PORT" ] ; then
	PORT="$DEFAULT_PORT"
fi

echo "$PORT" | grep -q '^[[:digit:]]\+$'
if [ $? -ne 0 ] ; then 
	echo "Error: Bad port number $PORT"
	exit 1
fi

if [ -z "$REMOTE_USER" ] ; then
	REMOTE_USER="$USER"
fi


# Decide on IP address

while IFS= read -r IFACE ; do
	MY_IP=$( ifconfig "$IFACE" | grep '\<inet\>' | sed -E 's/^.*inet[[:blank:]]+([[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}).*$/\1/' )

	if [ -n "$MY_IP" ] ; then
		break
	fi
done < <(ifconfig | grep '^en[[:digit:]]\+' | sed -E 's/^(en[[:digit:]]+):[[:blank:]]+.*$/\1/')

if [ -z "$MY_IP" ] ; then
	echo 'Can not do: you are not connected to any kind of Ethernet'
	exit 1
fi


# TODO: Restart server


# Connect to clients

while IFS= read -r CLIENT ; do
	echo "Connecting to $CLIENT as $REMOTE_USER"
	echo "$REMORE_SCRIPT" | sed "s/@IP@/$MY_IP/g" | sed "s/@PORT@/$PORT/g" | ssh -T "$REMOTE_USER"@"$CLIENT"
done < <(cat "$CONFIG" | grep ':' | grep -vi section | grep -o '[[:alnum:]\-_\.]\+' | sort -u | grep -v "$HOSTNAME")
