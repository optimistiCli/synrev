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
USAGE='Usage:
  synrev.sh [-c <confif.file>] [-p <port>] [-u <username>] 

Connect this keyboard and mouse of this computer to another 
computer(s) with synergy. Basically this script uses ssh reverse the 
client-server roles of synergy.

Options:
  -h Print this help and exit.
  -c Synergy server config file. This script reads it for the client 
     computer name(s) this computer keyboard and mouse will be 
     connected to. See http://synergy-project.org/wiki/Text_Config .
     If omitted defaults to .synergy.conf in home directory.
  -p A port number synergy server on this computer will use. Defaults
     to 24800.
  -u User name used to connect to other computers. Defaults to the 
     name of the user running this script.

Requirements:
  * Synergy server config should use resolvable host names for client
    names. Server name must be the host name of the computer runnung
    this script.
  * The computer that takes up the role of the synergy server must be 
    connected to Ethernet, wired or wireless.
  * The user should be able to ssh from this computer to the all the 
    clients (password or passwordless) using the same user name.
'

function brag_and_exit {
	if [ -n "$1" ] ; then
		ERR_MESSAGE='Error in synrev: '"$1"
		EXIT_CODE=1
	fi

	echo "${ERR_MESSAGE}"$'\\n\\n'"${USAGE}"
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
if [ -z "$SERVER_IP" ] ; then
	brag_and_exit 'No server IP'
fi

if [ -z "$SERVER_PORT" ] ; then
	brag_and_exit "No server port"
fi

if [ -z "$CLIENTNAME" ] ; then
	brag_and_exit "No client name"
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

"$SYNERGYC_PATH" -f --no-tray --debug FATAL --name "$CLIENTNAME" --enable-drag-drop --enable-crypto "$SERVER_IP":"$SERVER_PORT" >> /dev/null 2>&1  & 

sleep 2
EOR

#####################
### REMOTE SCRIPT ###
###      END      ###
#####################

# Inject synergy killer
eval "$FUNCTION_INJECTIONS"
REMORE_SCRIPT="$FUNCTION_INJECTIONS"$'\n\n'"$REMORE_SCRIPT"


# Decide on config file and port

while getopts ":c:p:u:h" opt ; do
	case $opt in
		h)
			echo "$USAGE"
			exit
			;;
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

	REMORE_SCRIPT="CLIENTNAME='$CLIENT'"$'\n'"SERVER_IP='$MY_IP'"$'\n'"SERVER_PORT='$PORT'"$'\n\n'"$REMORE_SCRIPT"
	echo "$REMORE_SCRIPT" | ssh -T "$REMOTE_USER"@"$CLIENT"
done < <(cat "$CONFIG" | grep ':' | grep -vi section | grep -o '[[:alnum:]\-_\.]\+' | sort -u | grep -v "$HOSTNAME")
