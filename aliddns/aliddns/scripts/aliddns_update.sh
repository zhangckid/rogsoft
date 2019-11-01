#!/bin/sh

source /koolshare/scripts/base.sh
eval `dbus export aliddns_`
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】'
https_lanport=`nvram get https_lanport`
if [ "$aliddns_enable" != "1" ]; then
    nvram set ddns_hostname_x=`nvram get ddns_hostname_old`
    echo "not enable"
    exit
fi

now=`echo_date`

die () {
    echo $1
    dbus set aliddns_last_act="$now: failed($1)"
}

[ "$aliddns_curl" = "" ] && aliddns_curl="curl -s --interface ppp0 whatismyip.akamai.com"
[ "$aliddns_dns" = "" ] && aliddns_dns="223.5.5.5"
[ "$aliddns_ttl" = "" ] && aliddns_ttl="600"

ip=`$aliddns_curl 2>&1` || die "$ip"

#support @ record nslookup
if [ "$aliddns_name" = "@" ];
then
    current_ip=`nslookup $aliddns_name $aliddns_dns 2>&1`
else
    current_ip=`nslookup $aliddns_name.$aliddns_domain $aliddns_dns 2>&1`
fi

if [ "$?" -eq "0" ]
then
    current_ip=`echo "$current_ip" | grep 'Address 1' | tail -n1 | awk '{print $NF}'`

    if [ "$ip" = "$current_ip" ];
    then
        echo "skipping"
        dbus set aliddns_last_act="$now: skipped($ip)"
        dbus set aliddns_last_act="$now: skipped($ip)"
        nvram set ddns_enable_x=1
        #web ui show without @.
        if [ "$aliddns_name" = "@" ] ;then
		nvram set ddns_hostname_x="$aliddns_domain"
        else
			ddns_custom_updated 1
			exit 0
		fi
        exit 0
    fi 
fi


timestamp=`date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ"`

urlencode() {
    # urlencode <string>
    out=""
    while read -n1 c
    do
        case $c in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out`printf '%%%02X' "'$c"`" ;;
        esac
    done
    echo -n $out
}

enc() {
    echo -n "$1" | urlencode
}

send_request() {
    local args="AccessKeyId=$aliddns_ak&Action=$1&Format=json&$2&Version=2015-01-09"
    local hash=$(echo -n "GET&%2F&$(enc "$args")" | openssl dgst -sha1 -hmac "$aliddns_sk&" -binary | openssl base64)
    curl -s "http://alidns.aliyuncs.com/?$args&Signature=$(enc "$hash")"
}

get_recordid() {
    grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"'
}

query_recordid() {
    send_request "DescribeSubDomainRecords" "SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&SubDomain=$1.$2&Timestamp=$timestamp"
}

update_record() {
    send_request "UpdateDomainRecord" "RR=$1&RecordId=$2&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$aliddns_ttl&Timestamp=$timestamp&Type=A&Value=$ip"
}

add_record() {
    send_request "AddDomainRecord&DomainName=$1" "RR=$2&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$aliddns_ttl&Timestamp=$timestamp&Type=A&Value=$ip"
}

#add support */%2A and @/%40 record
case  $aliddns_name  in                                                                                                                               
      \*)                                                                                                                                             
        aliddns_name=%2A                                                                                                                             
        ;;                                                                                                                                            
      \@)                                                                                                                                             
        aliddns_name=%40                                                                                                                             
        ;;                                                                                                                                            
      *)                                                                                                                                              
        aliddns_name=$aliddns_name                                                                                                                   
        ;;                                                                                                                                            
esac   

aliddns_record_id=`query_recordid $aliddns_name $aliddns_domain | get_recordid`

if [ "$aliddns_record_id" = "" ]
then
    aliddns_record_id=`add_record $aliddns_domain $aliddns_name | get_recordid`
    echo "added record $aliddns_record_id"
else
    update_record $aliddns_name $aliddns_record_id
    echo "updated record $aliddns_record_id"
fi

# save to file
if [ "$aliddns_record_id" = "" ]; then
    # failed
    dbus set aliddns_last_act="$now: failed"
    nvram set ddns_hostname_x=`nvram get ddns_hostname_old`
else
    dbus set aliddns_record_id=$aliddns_record_id
    dbus set aliddns_last_act="$now: success($ip)"
    nvram set ddns_enable_x=1
    #web ui show without @.
	if [ "$aliddns_name" = "%40" ] ;then
	 	nvram set ddns_hostname_x="$aliddns_domain"
		nvram set ddns_updated="1"
		nvram commit
	else
	 	nvram set ddns_hostname_x="$aliddns_name"."$aliddns_domain"
		nvram set ddns_updated="1"
		nvram commit
	fi
fi
