#!/bin/bash

#rename mobile devices to serial number
#version 1.0 november 18 2024

JAMF_PRO_URL=""
JAMF_PRO_USERNAME=""
JAMF_PRO_PASSWORD=""

#Variable declarations
bearer_token=""
bearer_token_expiration_epoch="0"

requestBearerToken() {
	bearer_token_response=$(curl -s -u "$JAMF_PRO_USERNAME":"$JAMF_PRO_PASSWORD" "$JAMF_PRO_URL"/api/v1/auth/token -X POST)
	bearer_token=$(echo "$bearer_token_response" | plutil -extract token raw -)
	bearer_token_expiration=$(echo "$bearer_token_response" | plutil -extract expires raw - | awk -F . '{print $1}')
	bearer_token_expiration_epoch=$(date -j -f "%Y-%m-%dT%T" "$bearer_token_expiration" +"%s")
}

getValidBearerToken() {
	current_epoch_utc=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
	if [[ tokenExpirationEpoch -gt current_epoch_utc ]]
	then
		echo "Token valid until the following epoch time: " "$bearer_token_expiration_epoch"
	else
		echo "No valid token available, getting new token"
		requestBearerToken
	fi
}

invalidateToken() {
	invalidate_token_response_code=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearer_token}" $JAMF_PRO_URL/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${invalidate_token_response_code} == 204 ]]
	then
		echo "Token successfully invalidated"
		bearer_token=""
		bearer_token_expiration_epoch="0"
	elif [[ ${invalidate_token_response_code} == 401 ]]
	then
		echo "Token already invalid"
	else
		echo "An unknown error occurred invalidating the token"
	fi
}

getValidBearerToken

get_mobile_devices_response=$(curl -f -s -X GET $JAMF_PRO_URL/JSSResource/mobiledevices \
		-H "accept: application/xml" \
		-H "Authorization: Bearer ${bearer_token}"
)
mobile_devices_count=$(echo $get_mobile_devices_response | xmllint --xpath "/mobile_devices/size/text()" -)

if [ $mobile_devices_count -eq 0 ]; then
	echo "No mobile devices found."
else
	echo "$mobile_devices_count devices found."
	mobile_device_serials=$(echo $get_mobile_devices_response | xmllint --xpath "/mobile_devices/*[name!=serial_number]/serial_number/text()" -)
	
	for mobile_device_serial_number in $mobile_device_serials
	do
		curl -f -s -X PUT $JAMF_PRO_URL/JSSResource/mobiledevices/serialnumber/$mobile_device_serial_number \
		-H 'accept: application/xml' \
		-H 'content-type: application/xml' \
		-H "Authorization: Bearer $bearer_token" \
		-d "
		<mobile_device>
			<general>
				<name>$mobile_device_serial_number</name>
			</general>
		</mobile_device>

	"
	done

fi

invalidateToken

exit 0
