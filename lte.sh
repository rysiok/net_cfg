#!/bin/sh

PHONE="+48728943990"		# notify via sms
TIMEOUT=5			# curl req timeout [sec]
OPTIONS="-s"			# curl options
ENDPOINT="192.168.8.1"		# HiLink endpoint

sms_get_token() {
	cc=`curl --connect-timeout $TIMEOUT $OPTIONS -X GET http://$ENDPOINT/api/webserver/SesTokInfo`
	c=`echo "$cc"| grep SessionID=| cut -b 10-147`
	t=`echo "$cc"| grep TokInfo| cut -b 10-41`
}

sms_set_read() {
	id=$1
	sms_get_token
	curl --connect-timeout $TIMEOUT $OPTIONS http://$ENDPOINT/api/sms/set-read \
	-H "Cookie: $c" -H "__RequestVerificationToken: $t" \
	--data "<request><Index>$id</Index></request>"
}

sms_sent() {
	to=$1
	text=$2
	sms_get_token
	curl --connect-timeout $TIMEOUT $OPTIONS -X POST http://$ENDPOINT/api/sms/send-sms \
	-H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
	-H "Cookie: $c" -H "__RequestVerificationToken: $t" \
	--data "<request><Index>-1</Index><Phones><Phone>$to</Phone></Phones><Sca></Sca><Content>$text</Content><Length>-1</Length><Reserved>1</Reserved><Date>-1</Date></request>"
}

mobile_data_switch(){
	mode=$1	# 1 enable, 0 disable
	sms_get_token
	curl --connect-timeout $TIMEOUT $OPTIONS http://$ENDPOINT/api/dialup/mobile-dataswitch \
	-H "Cookie: $c" -H "__RequestVerificationToken: $t" \
	--data "<request><dataswitch>$mode</dataswitch></request>"
}

process_lte_status()
{
	lte=$(echo "$1" | grep LTE)
	on=$(echo "$1" | grep "zostala wlaczona")
	off=$(echo "$1" | grep "zostala wylaczona")

	if [ ! -z "$lte" ] && [ ! -z "$off" ] ; then

		echo "Wylaczanie transmisji danych LTE ..."
		mobile_data_switch 0

		echo "Informacja o wylaczeniu LTE ..."
		sms_sent $PHONE "DIL zostala wylaczona. Blokowanie internetu..."

		echo "aktywacja uslugi ..."
		sms_sent "111" "START.289"


	elif [ ! -z "$lte" ] && [ ! -z "$on" ] ; then

		echo "Wlaczanie transmisji danych LTE ..."
		mobile_data_switch 1

		echo "Informacja o wlaczeniu LTE ..."
		sms_sent $PHONE "DIL zostala uruchomiona. Przywracanie internetu..."
	else
		#forward
		sms_sent $PHONE "$1"
	fi
}

process_sms_list() {
	sms_get_token
	data=$(curl --connect-timeout $TIMEOUT $OPTIONS http://$ENDPOINT/api/sms/sms-list \
		-H "Cookie: $c" -H "__RequestVerificationToken: $t" \
		--data "<request><PageIndex>1</PageIndex><ReadCount>20</ReadCount><BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>1</UnreadPreferred></request>")
	#echo "$data"

	#TODO: remove cr/lf in data in text in tags

	process=0
	sms_id=-1
	echo "$data" | while read line
	do
		if [ $process -eq 0 ]; then
			unread=$(echo "$line" | grep Smstat | cut -d '>' -f2 | cut -d '<' -f1)
			if [ "$unread" = "0" ]; then
				echo "unread - processing ..."
				process=1
			fi
		else	#process=1
			if [ $sms_id -eq -1 ]; then
				id=$(echo "$line" | grep Index | cut -d '>' -f2 | cut -d '<' -f1)
				if [ ! -z "$id" ]; then
					echo "	id: $id"
					sms_id="$id"
				fi
			else
				content=$(echo "$line" | grep Content | cut -d '>' -f2 | cut -d '<' -f1)
				if [ ! -z "$content" ]; then
					echo "	content: $content"

					process_lte_status "$content"

					echo "mark as read $sms_id ..."
					sms_set_read $sms_id

					process=0
					sms_id=-1
				fi
			fi
		fi
	done
}

process_sms_list

exit 0
