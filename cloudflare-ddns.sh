#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                 # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
record_name=""                                      # Which record you want to be synced
ttl="600"                                          # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false


###########################################
## Check if we have a public IP
###########################################
ipv6_regex='^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}$'
ipv6=$(ip -o a show|grep -v br0|grep inet6|grep global|awk '{print $4}'|cut -d'/' -f1)

# Use regex to check for proper IPv4 format.
if echo "$ipv6"| grep -Eq $ipv6_regex; then
    logger -s "DDNS Updater: Failed to find a valid IP."
    exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

logger "DDNS Updater: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

###########################################
## Check if the domain has an A record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  logger -s "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IP
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"([a-z0-9:]*)".*/\1/')
# Compare if they're the same
if [[ $ipv6 == $old_ip ]]; then
  logger "DDNS Updater: IP ($ipv6) for ${record_name} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')

###########################################
## Change the IP@Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"AAAA\",\"name\":\"$record_name\",\"content\":\"$ipv6\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")
if [ $? -ne 0 ];then
    logger -s 'update failed'
    exit 1
fi
    echo ok
