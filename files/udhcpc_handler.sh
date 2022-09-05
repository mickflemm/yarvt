#!/bin/bash

if [[ -z ${1} ]]; then
	echo "No action provided"
	return -1;
fi

RESOLV_CONF="/etc/resolv.conf"
NTP_CONF="/etc/ntp.conf"

case "${1}" in
	defconfig)
		ip addr flush dev ${interface}
		;;
	renew | bound)
		ip addr add ${ip}/${mask} dev ${interface}
		if [[ -n "${router}" ]]; then
			ip route add default via ${router%% *} dev ${interface}
		fi
		if [[ -n ${domain} ]]; then
			echo "search ${domain}" > ${RESOLV_CONF}
		fi
		for i in ${dns}; do
			echo "nameserver ${i}" >> ${RESOLV_CONF}
		done
		for i in ${ntpsrv}; do
			echo "server ${1}" >> ${NTP_CONF}
		done
		echo "server time.google.com" >> ${NTP_CONF}
		if [[ -n "${hostname}" ]]; then
			hostname "${hostname}"
		fi
		;;
esac

return 0

