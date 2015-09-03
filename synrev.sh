#!/bin/bash

# Remotely start synergy client on a mac
# Usage: rem-sync.sh [-c <config>] [-p <port>] [-u <remote username>]

DEFAULT_CONFIG="$HOME/.synergy.conf"
DEFAULT_PORT='24800'


##################
### INJECTIONS ###
###   START    ###
##################

read -d '' FUNCTION_INJECTIONS << 'EOK'
function brag_and_exit {
	if [ -n "$1" ] ; then
		ERR_MESSAGE=$'synrev error: '"$1"
		EXIT_CODE=1
	fi

	echo "${ERR_MESSAGE}${USAGE}"
	logger "${ERR_MESSAGE}"

	exit $EXIT_CODE
}

function kill_all_synergies {
	echo -n 'Killing stale synergies...'
	while killall -m '^[Ss]ynergy[cs]?$' 2> /dev/null ; do
		sleep 1
		echo -n '.'
	done
	echo ' done'
}
EOK

##################
### INJECTIONS ###
###    END     ###
##################

#####################
### REMOTE SCRIPT ###
###     START     ###
#####################

# Beware of backslashes! Double them or else :-)
read -d '' REMORE_SCRIPT << 'EOR'
SERVER_IP='@IP@'
SERVER_PORT='@PORT@'

if [ -z "$SERVER_IP" ] ; then
	brag_and_exit 'No server IP'
fi

echo "$SERVER_IP" | grep -q '^[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}$'
if [ $? -ne 0 ] ; then 
	SERVER_DNS=$(host "$SERVER_IP")
	if [ $? -ne 0 ] ; then
		brag_and_exit "Server $SERVER_IP not found"
	fi
	SERVER_IP=$(echo "$SERVER_DNS" | grep -o '[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}')
fi

if [ -n "$SERVER_PORT" ] ; then
	echo "$SERVER_PORT" | grep -q '^[[:digit:]]\\+$'
	if [ $? -ne 0 ] ; then 
		brag_and_exit "Bad port number $SERVER_PORT"
	fi
else 
	SERVER_PORT='24800'
fi

if uname | grep -qi '\\<darwin\\>' ; then
	PATH=/Applications/Synergy.app/Contents/MacOS:"$HOME"/Applications/Synergy.app/Contents/MacOS:"$PATH"
fi

SYNERGYC_PATH=$(which synergyc)

if [ $? -ne 0 ] ; then
	brag_and_exit 'Can not find synergyc binary'
fi

kill_all_synergies


echo Connecting back to "$SERVER_IP":"$SERVER_PORT"

"$SYNERGYC_PATH" -f --no-tray --debug FATAL --name "$HOSTNAME" --enable-drag-drop --enable-crypto "$SERVER_IP":"$SERVER_PORT" >> /dev/null 2>&1  & 

sleep 3

EOR

#####################
### REMOTE SCRIPT ###
###      END      ###
#####################

# Inject synergy killer
eval "$FUNCTION_INJECTIONS"
REMORE_SCRIPT="$FUNCTION_INJECTIONS"$'\n\n'"$REMORE_SCRIPT"


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
	brag_and_exit "Config file not found $CONFIG"
fi

if [ -z "$PORT" ] ; then
	PORT="$DEFAULT_PORT"
fi

echo "$PORT" | grep -q '^[[:digit:]]\+$'
if [ $? -ne 0 ] ; then 
	brag_and_exit "Bad port number $PORT"
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
	brag_and_exit 'Can not do: you are not connected to any kind of Ethernet'
fi


# Restart server

if uname | grep -qi '\<darwin\>' ; then
	PATH=/Applications/Synergy.app/Contents/MacOS:"$HOME"/Applications/Synergy.app/Contents/MacOS:"$PATH"
fi

SYNERGYS_PATH=$(which synergys)

if [ $? -ne 0 ] ; then
	brag_and_exit 'Can not find synergys binary'
fi

kill_all_synergies

"$SYNERGYS_PATH" -f --no-tray --debug FATAL --name "$HOSTNAME" --enable-drag-drop --enable-crypto -c "$CONFIG" --address :"$PORT" 2>> /dev/null & disown


# Connect to clients

while IFS= read -r CLIENT ; do
	echo "Connecting to $CLIENT as $REMOTE_USER"
	echo "$REMORE_SCRIPT" \
		| sed "s/@IP@/$MY_IP/g" \
		| sed "s/@PORT@/$PORT/g" \
		| ssh -T "$REMOTE_USER"@"$CLIENT"
done < <(cat "$CONFIG" | grep ':' | grep -vi section | grep -o '[[:alnum:]\-_\.]\+' | sort -u | grep -v "$HOSTNAME")
