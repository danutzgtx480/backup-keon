#!/system/bin/sh
# Copyright (c) 2012, Code Aurora Forum. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Code Aurora nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
echo "begin the save pcap script."
target=`getprop ro.product.device`
BUSYBOX=/data/busybox/busybox

chmod 755 $BUSYBOX

# verify number of arguments
if $BUSYBOX [ $# -lt 1 ]; then
	echo "lack of argumnet"
	exit 1
fi

iface=$1
debug_property=persist.debug.$iface

case "$1" in
    "rmnet0") dev_property="persist.debug.svrmnetpcap"
    ;;
    "wlan0") dev_property="persist.debug.svwlanpcap"
    ;;
esac

echo "debug property:"$debug_property" and dev property:"$dev_property

verify_tcmpdump_has_up()
{
	index=0
	setprop $debug_property 1
	ps tcpdump | $BUSYBOX awk '{print $3}' | while read ppid
	do
		if $BUSYBOX [ $index -gt 0 ] && $BUSYBOX [ $ppid -eq $$ ]; then
			setprop $debug_property 2
			break;
		fi
		index=`$BUSYBOX expr $index + 1`
	done
	sleep 2
	script_status=`getprop $debug_property`
	if $BUSYBOX [ $script_status -eq 2 ]; then
		return 0
	else
		# need to turn off property since this network interface has down
		return 1
	fi
}


case "$target" in
	"msm7627a_sku1" | "msm7627a_sku3" | "msm7627a_sku5" | "msm7627a")
	logpath=/sdcard/logs/tcpdump
	time=$(date +%Y%m%d%H%M%S)
	day=$(date +%j)

	mkdir $logpath

	#make sure net interface is available
	retryCount=0
	setprop $debug_property 0
	while true; do
		netcfg | $BUSYBOX awk '{print $1,$2}' | while read str1 str2
		do
			if $BUSYBOX [ $str1 = $iface ] && $BUSYBOX [ $str2 = "UP" ]; then
				setprop $debug_property 1
				break
			fi
		done

		rmnetup=`getprop $debug_property`
		if $BUSYBOX [ $rmnetup -eq 1 ]; then
			echo "already up!"
			break
		fi

		retryCount=`$BUSYBOX expr $retryCount + 1`
		echo "retry "$retryCount" of 20"
		if $BUSYBOX [ $retryCount -gt 19 ]; then
			echo RetryTimeOut
			setprop $dev_property 0
			exit 1
		fi
		sleep 3
	done

	#then start save pcap to sd card
	tcpdump -i $iface -nnXSs 96 -w $logpath/logs-$iface-$day-$time.pcap &

	sleep 3
	verify_tcmpdump_has_up
	if $BUSYBOX [ $? -eq 1 ];then
		setprop $dev_property 0
		exit 2
	fi
	# monitor the log file's size
	while true; do
		verify_tcmpdump_has_up
		if $BUSYBOX [ $? -eq 1 ];then
			setprop $dev_property 0
			exit 2
		fi
	    filesize=`ls -l $logpath/logs-$iface-$day-$time.pcap | $BUSYBOX awk '{print $4}'`
		if $BUSYBOX [ $filesize -gt 52428800 ] ; then
			index=0
			ps tcpdump | $BUSYBOX awk '{print $2,$3}' | while read pid ppid
			do
				if $BUSYBOX [ 0 -eq $index ]; then
					index=`$BUSYBOX expr $index + 1`
				elif $BUSYBOX [ $ppid -eq $$ ]; then
					kill -9 $pid
				fi
			done

			time=$(date +%Y%m%d%H%M%S)
			day=$(date +%j)
			tcpdump -i $iface -nnXSs 96 -w $logpath/logs-$iface-$day-$time.pcap &
			pid_tcpdump=$!
	    fi
	    sleep 600
	done
esac
