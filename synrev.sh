#!/bin/bash

# Remotely start synergy client on a mac
# Usage: rem-sync.sh [-c <config>] [-p <port>] [-U <remote username>]

DEFAULT_CONFIG="$HOME/.synergy.conf"
DEFAULT_PORT='24800'

#####################
### REMOTE SCRIPT ###
###     START     ###
#####################

read -d '' REMORE_SCRIPT << 'EOREMOTE'
#!/bin/bash

# Beware of backslashes! Double them or else :-)

SERVER_IP='@IP@'
SERVER_PORT='@PORT@'

function brag_and_exit {
	if [ -n "$1" ] ; then
		err_message=$'synrev error: '"$1"
		exit_code=1
	fi

	logger "${err_message}${usage}"

	exit $exit_code
}

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
		echo "Bad port number $SERVER_PORT"
		exit 1
	fi
else 
	SERVER_PORT='24800'
fi

echo Connecting back to "$SERVER_IP":"$SERVER_PORT"

if uname | grep -qi '\\<darwin\\>' ; then
	PATH=/Applications/Synergy.app/Contents/MacOS:"$HOME"/Applications/Synergy.app/Contents/MacOS:"$PATH"
fi

SYNERGYC_PATH=$(which synergyc)

if [ $? -ne 0 ] ; then
	brag_and_exit 'Can not find synergyc binary'
fi

while IFS= read -r PS_LINE ; do
	PS_LINE_ARRAY=($PS_LINE)
	PS_COMMAND="${PS_LINE_ARRAY[10]}"

	echo "$PS_COMMAND" | grep -iq 'synergy[sc]\\?$'
	if [ $? -ne 0 ] ; then
		continue
	fi

	PS_PID="${PS_LINE_ARRAY[1]}"
	kill "$PS_PID"

	if [ $? -ne 0 ] ; then
		echo "Error: Can not kill old process $PS_PID: $PS_COMMAND"
		exit 1
	fi

	echo -n "Waiting there for $PS_COMMAND ($PS_PID) to exit..."
	while ps "$PS_PID" >> /dev/null ; do
		echo -n '.'
		sleep $(echo '1 / 2' | bc -l)
	done
	echo ' done'

done < <(ps uax)


"$SYNERGYC_PATH" -f --no-tray --debug FATAL --name "$HOSTNAME" --enable-drag-drop --enable-crypto "$SERVER_IP":"$SERVER_PORT" 2>> /dev/null & disown 

EOREMOTE

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


# Restart server

if uname | grep -qi '\<darwin\>' ; then
	PATH=/Applications/Synergy.app/Contents/MacOS:"$HOME"/Applications/Synergy.app/Contents/MacOS:"$PATH"
fi

SYNERGYS_PATH=$(which synergys)

if [ $? -ne 0 ] ; then
	echo 'Error: Can not find synergys binary'
	exit 1
fi

while IFS= read -r PS_LINE ; do
	PS_LINE_ARRAY=($PS_LINE)
	PS_COMMAND="${PS_LINE_ARRAY[10]}"

	echo "$PS_COMMAND" | grep -iq 'synergy[sc]\?$'
	if [ $? -ne 0 ] ; then
		continue
	fi

	PS_PID="${PS_LINE_ARRAY[1]}"
	#kill "$PS_PID"

	if [ $? -ne 0 ] ; then
		echo "Error: Can not kill old process $PS_PID: $PS_COMMAND"
		exit 1
	fi

	#echo -n "Waiting here for $PS_COMMAND ($PS_PID) to exit..."
	#while ps "$PS_PID" >> /dev/null ; do
	#	echo -n '.'
	#	sleep $(echo '1 / 2' | bc -l)
	#done
	#echo ' done'

done < <(ps uax)

#"$SYNERGYS_PATH" -f --no-tray --debug FATAL --name "$HOSTNAME" --enable-drag-drop --enable-crypto -c "$CONFIG" --address :"$PORT" 2>> /dev/null & disown


# Connect to clients

while IFS= read -r CLIENT ; do
	echo "Connecting to $CLIENT as $REMOTE_USER"
	echo "$REMORE_SCRIPT" | sed "s/@IP@/$MY_IP/g" | sed "s/@PORT@/$PORT/g" | ssh -T "$REMOTE_USER"@"$CLIENT"
done < <(cat "$CONFIG" | grep ':' | grep -vi section | grep -o '[[:alnum:]\-_\.]\+' | sort -u | grep -v "$HOSTNAME")
