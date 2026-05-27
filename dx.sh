houseRule () {
cat <<EOF
01. let keep the kiss principle for the dx script
02. you may directly execute each function wrapped commands
EOF
}

houseKey () {
  aws ssm get-parameter --name 'orcahouse-mgmt' --output text --with-decryption --query 'Parameter.Value' > ~/.ssh/orcahouse-mgmt # pragma: allowlist secret
  chmod 600 ~/.ssh/orcahouse-mgmt
  ls -l ~/.ssh/orcahouse-mgmt
}

houseInstance () {
  aws ec2 describe-instances \
    --filters 'Name=tag:Name,Values=orcahouse-mgmt-*' \
    --output text \
    --query 'Reservations[*].Instances[*].InstanceId'
}

houseEndpoint () {
  aws redshift-serverless get-workgroup --workgroup-name orcahouse-dev --output text --query 'workgroup.endpoint.address'
}

houseHost () {
  IP_ADDR="127.0.0.1"
  DOMAIN=$(houseEndpoint)

  # Check if the entry already exists
  if getent hosts "$DOMAIN" > /dev/null 2>&1; then
      echo "Entry for $DOMAIN already exists. Doing nothing."
  else
      echo "Entry for $DOMAIN not found. Adding to /etc/hosts..."
      # Append the entry using sudo and tee to handle permissions safely
      echo "$IP_ADDR $DOMAIN" | sudo tee -a /etc/hosts > /dev/null
      echo "Successfully added $IP_ADDR $DOMAIN to /etc/hosts"
  fi
}

houseCheckHost () {
  getent hosts "$(houseEndpoint)"
}

houseUndoHost () {
  IP_ADDR="127.0.0.1"
  DOMAIN=$(houseEndpoint)
  ENTRY="$IP_ADDR $DOMAIN"

  # Check for the exact line in /etc/hosts (ignoring trailing whitespace)
  if grep -Fxq "$ENTRY" /etc/hosts; then
      echo "Exact entry '$ENTRY' found. Removing it..."

      # Use sed to delete the exact line and save the file in-place
      sudo sed -i "\|#|!{s|^[[:space:]]*${IP_ADDR}[[:space:]]\+${DOMAIN}[[:space:]]*$||; /^$/d}" /etc/hosts

      echo "Entry removed successfully."
  else
      echo "Exact entry '$ENTRY' does not exist. Doing nothing."
  fi
}

houseTunnel () {
  ssh -f -N -L 127.0.0.1:5439:"$(houseEndpoint)":5439 \
    ubuntu@"$(houseInstance)" -i ~/.ssh/orcahouse-mgmt \
    -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id %h'
}

houseTunnelFg () {
  # keep tunnel in the foreground, ctrl+c to end the tunnel session
  ssh -v -N -L 127.0.0.1:5439:"$(houseEndpoint)":5439 \
    ubuntu@"$(houseInstance)" -i ~/.ssh/orcahouse-mgmt \
    -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id %h'
}

houseStatus () {
  # ps aux | grep '[s]sh'
  # ps aux | grep '[o]rcahouse-mgmt'
  ps aux | grep '[o]pen-tunnel'
}

houseStop () {
  # kill <PID>
  pkill -f "open-tunnel"
}

houseForward () {
  aws ssm start-session \
    --target "$(houseInstance)" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"portNumber\":[\"5439\"],\"localPortNumber\":[\"5439\"],\"host\":[\"$(houseEndpoint)\"]}"
}

houseCred () {
  DBT_ENV_SECRET_HOST=$(houseEndpoint)
  export DBT_ENV_SECRET_HOST
  export DBT_ENV_SECRET_USER="dbt" # pragma: allowlist secret
  env | grep DBT
}

houseClean () {
  unset DBT_ENV_SECRET_HOST DBT_ENV_SECRET_PASSWORD DBT_ENV_SECRET_USER
  env | grep DBT
}
