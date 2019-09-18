#!/bin/bash
#####################################################################
# changes:
# 20190917 - created script.
#####################################################################

#####################################################################
# Default Variables 
#####################################################################
SVER='1.00-001'
SDATE="2019 09 17"
MyLongName=$(basename $BASH_SOURCE)
MyName=$(echo $MyLongName | cut -f 1 -d '.')
USERNAME=root
ADMINNODE=0
OTHERNODE=0
RUNSCRIPT=0

# Spinner
i=1
sp="/-\|"

# Variables that should be modified to meet SES4 DeepSea Deploys need.
#
# for SES5, C2 cluster!
#
AdminDnsName=node1
SESNodes="node1 node2 node3 node4 node5 node6 node7"

#####################################################################
# General Function Definitions
#####################################################################
title() {
	echo "============================================================"
	echo "    Script Name: - $MyLongName"
	echo "    Script Version: $SVER"
	echo "    Script Date: $SDATE"
	echo 
	echo " This script is used to reinstall the salt-master & minion packages."
	echo "============================================================"
	echo
}

show_help() {
    echo " Usage: $MyName [OPTION]"
    echo
    echo " Requirements: "
    echo "  -Run on Admin node. "
    echo "  -HostName & AdminDnsName need to be the same. "
    echo "  -AdminDnsName is the DNS name of the host that will be the admin node. "
    echo "  -SESNodes is a list of all nodes that will be in the cluster. "
    echo "  -Installs salt-master & salt-minion packages on the admin node. "
    echo "  -Installs salt-minion packages on other nodes. "
    echo
    echo " Edit the following variables before running: "
    echo "    AdminDnsName "
    echo "    SESNodes "
    echo
    echo "  -h Print this help screen "
    echo "  -r Allow the script to run (disengage safety) "
    echo " Example: "
    echo " ./$MyName.sh -h "
    echo " ./$MyName.sh -r "
    echo
}

last_message() {
	echo " Use 'salt-key --list-all' on the master to list minons:" 2>&1 | tee -a $LOGFILE
	echo " Use 'salt-key --accept-all' to accept all keys" 2>&1 | tee -a $LOGFILE
}

#####################################################################
# Parse command line parameters 
#####################################################################
options_found=0
#if (($# == 0)); then
#  echo " no parameters "
#fi

# Number of Parameters
##echo "--$#--"
 
while getopts ":hr" opt; do
	options_found=1
	case $opt in
    \?)	echo "Invalid option: -$OPTARG" >&2
		exit 1
		;;
    :)	echo "Option -$OPTARG requires an argument." >&2
		exit 1
		;;
	h) 	title; show_help; exit 0 ;;
		#echo "Help goes here!" >&2
		#;;
    r)	echo "-r was triggered, Parameter: $OPTARG" 
		RUNSCRIPT=1 >&2
		;;
	esac
done

#===========================
# Which node are we running on.
if [ "$HOSTNAME" = "$AdminDnsName" ]; then
	clear
	#echo " $HOSTNAME = $AdminDnsName, Configuring as admin node..."
	echo " Reinstalling salt-master and salt-minion packages:"
	ADMINNODE=1
	OTHERNODE=1
else
	clear
	echo " NOT configured as admin node..."
	echo "    Configured HostName:     $HOSTNAME "
	echo "    Configured AdminDnsName: $AdminDnsName "
	echo " Exiting..."
	echo
	#echo " Installing salt-minion for mon's, osd's, etc..."
	#OTHERNODE=1
	show_help
	exit 0
fi

#===========================
# Do you want to continue?
echo
echo "    Configured HostName:     $HOSTNAME "
echo "    Configured AdminDnsName: $AdminDnsName "
echo "    Configured SESNodes: "
echo "    $SESNodes "
echo
while true; do
	read -p " Do you wish to continue with this configuration?" yn
	case $yn in
		[Yy]* ) break;;
		[Nn]* ) exit 0;;
		* ) echo "Please answer yes or no.";;
	esac
done	

#===========================
# -r
if ((!RUNSCRIPT)); then
	echo
	echo " missing -r paramter"
	echo
	show_help
	exit 0
fi

#===========================
# No option found
#if ((!options_found)); then
#  echo "no options found"
#  title; show_help; exit 0
#fi

#####################################################################
# Done Parsing Command Line.
#####################################################################

#####################################################################
# Main 	
#####################################################################
#===========================
# Setup logging for this host.
LOGFILE="$PWD/$MyName-$(date "+%Y%m%d-%H%M%S").log"
echo "--$LOGFILE--"
touch $LOGFILE
echo "$(date "+%m%d%Y %T") : Starting work" >> $LOGFILE 2>&1

while (true)
do
#===========================
# Requirements:
	#===========================
	#ping nodes to make sure they are there.
	for HOSTNAME in ${SESNodes} ; do
		ping -c 1 $HOSTNAME &> /dev/null
		if [ $? -eq 0 ]; then
			echo “$HOSTNAME responded.”
		else 
			echo “$HOSTNAME failed to responded.”
			exit 1
		fi
	done

	#==========================
	# Stop/Disable All minions.
	REMOTEEXECUTE1="systemctl stop salt-minion; systemctl disable salt-minion"
	echo " Stop/Disable ALL minions. " 2>&1 | tee -a $LOGFILE
	echo " Remote Execute commands on nodes. " 2>&1 | tee -a $LOGFILE
	echo " Remote commands: $REMOTEEXECUTE1 " 2>&1 | tee -a $LOGFILE
	for HOSTNAME in ${SESNodes} ; do
		if [ "$HOSTNAME" = "$AdminDnsName" ]; then
			echo " Stop/Disable: $HOSTNAME " 2>&1 | tee -a $LOGFILE
			systemctl stop salt-minion
			systemctl disable salt-minion
		else
			echo " Remote Execute on $HOSTNAME " 2>&1 | tee -a $LOGFILE
			( ssh -o StrictHostKeyChecking=no -l ${USERNAME} ${HOSTNAME} ${REMOTEEXECUTE1} >/dev/null 2>&1 ) &
		fi
	done
	
	echo "waiting....." 2>&1 | tee -a $LOGFILE

	child_count=$(($(pgrep --parent $$ | wc -l) - 1))
	echo "SubShells Created: $child_count " 2>&1 | tee -a $LOGFILE
	echo -n ' '
	while [ "$(($(pgrep --parent $$ | wc -l) - 1))" -gt 0 ]; do
        sleep .5
        children=$(($(pgrep --parent $$ | wc -l) - 1))
        echo -ne "SubShells Running: $children" " \b${sp:i++%${#sp}:1}" \\r
	done

	wait
	# Check return codes and/or log files from remote hosts.
	echo "Finished setting up remote hosts with salt-minions. " 2>&1 | tee -a $LOGFILE

	#============================
	# This is for Admin node only!
	if ((ADMINNODE)); then
		#=====================
		echo " stop/disable minion. " 2>&1 | tee -a $LOGFILE
		systemctl stop salt-minion >> $LOGFILE 2>&1
		systemctl disable salt-minion >> $LOGFILE 2>&1
		echo " stop/disable master. " 2>&1 | tee -a $LOGFILE
		systemctl stop salt-master >> $LOGFILE 2>&1
		systemctl disable salt-master >> $LOGFILE 2>&1
		zypper --non-interactive rm salt-master salt-minion >> $LOGFILE 2>&1
		rm -rf /var/cache/salt >> $LOGFILE 2>&1
		rm -rf /etc/salt >> $LOGFILE 2>&1
		zypper --non-interactive in salt-master salt-minion deepsea >> $LOGFILE 2>&1
		systemctl enable salt-master.service >> $LOGFILE 2>&1
		systemctl start salt-master.service >> $LOGFILE 2>&1
		echo "master: $AdminDnsName" > /etc/salt/minion.d/master.conf
		cat /etc/salt/minion.d/master.conf 2>&1 | tee -a $LOGFILE
		systemctl enable salt-minion.service >> $LOGFILE 2>&1
		systemctl start salt-minion.service >> $LOGFILE 2>&1
		cat  /etc/salt/minion_id
		#salt-call --local key.finger
		#salt-key -F
		#salt-key --list-all
		#salt-key --accept-all
		#=====================
	fi	

	#===========================
	# Remote execute commands on nodes
	# This can be reworked to check return codes
		#local RESULTS
		#RESULTS=$(ssh user@server /usr/local/scripts/test_ping.sh)
		#echo $?
	REMOTEEXECUTE2=" zypper --non-interactive rm salt-minion; rm -rf /var/cache/salt; rm -rf /etc/salt; zypper --non-interactive in salt-minion; echo 'master: $AdminDnsName' > /etc/salt/minion.d/master.conf; cat /etc/salt/minion.d/master.conf; systemctl enable salt-minion.service;systemctl start salt-minion.service"
	# salt-call --local key.finger
	echo " Remote Execute commands on nodes. " 2>&1 | tee -a $LOGFILE
	echo " Remote commands: $REMOTEEXECUTE2 " 2>&1 | tee -a $LOGFILE
	for HOSTNAME in ${SESNodes} ; do
		if [ "$HOSTNAME" = "$AdminDnsName" ]; then
			echo " Skiping: $HOSTNAME " 2>&1 | tee -a $LOGFILE
		else
			echo " Remote Execute on $HOSTNAME " 2>&1 | tee -a $LOGFILE
			( ssh -o StrictHostKeyChecking=no -l ${USERNAME} ${HOSTNAME} ${REMOTEEXECUTE2} >/dev/null 2>&1 ) &
		fi
	done
	
	echo "waiting....." 2>&1 | tee -a $LOGFILE

	child_count=$(($(pgrep --parent $$ | wc -l) - 1))
	echo "SubShells Created: $child_count " 2>&1 | tee -a $LOGFILE
	echo -n ' '
	while [ "$(($(pgrep --parent $$ | wc -l) - 1))" -gt 0 ]; do
        sleep .5
        children=$(($(pgrep --parent $$ | wc -l) - 1))
        echo -ne "SubShells Running: $children" " \b${sp:i++%${#sp}:1}" \\r
	done

	wait
	# Check return codes and/or log files from remote hosts.
	echo "Finished setting up remote hosts with salt-minions. " 2>&1 | tee -a $LOGFILE
	
	#===========================
	# Back to Admin node only to finish up.
	if ((ADMINNODE)); then
		#===========================
		# Now validate salt keys
		sleep 5
		salt-key --list-all
		echo ""
		PS3="Answer: 1-yes 2-no 3-refresh "
		echo " Use this configuration? "
		select answer in yes no refresh
		do
			case $answer in
				yes) break;;
				no) last_message; exit 0;;
				refresh) echo " Use this configuration? "; salt-key --list-all;;
				#*) "Answer: 1-yes 2-no 3-refresh";;
			esac
		done
		salt-key --accept-all
		sleep 10
		
		#===========================
		# Test to see if works. 
		salt \* test.ping
		
        #===========================
		#/srv/pillar/ceph/deepsea_minions.sls
        #echo " salt '*' grains.append deepsea default " 2>&1 | tee -a $LOGFILE
        #salt '*' grains.append deepsea default >> $LOGFILE 2>&1
	fi 
	exit
done
#####################################################################
# THE END !!
#####################################################################
