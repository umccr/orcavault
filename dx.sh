house_rule () {
cat <<EOF
01. let keep the kiss principle for the dx script
02. you may directly execute each function wrapped commands
EOF
}

house_key () {
  aws ssm get-parameter --name 'orcahouse-mgmt' --output text --with-decryption --query 'Parameter.Value' > ~/.ssh/orcahouse-mgmt # pragma: allowlist secret
  chmod 600 ~/.ssh/orcahouse-mgmt
  ls -l ~/.ssh/orcahouse-mgmt
}

house_instance () {
  aws ec2 describe-instances \
    --filters 'Name=tag:Name,Values=orcahouse-mgmt-*' \
    --output text \
    --query 'Reservations[*].Instances[*].InstanceId'
}

house_endpoint () {
  aws redshift-serverless get-workgroup --workgroup-name orcahouse-dev --output text --query 'workgroup.endpoint.address'
}

house_host () {
  IP_ADDR="127.0.0.1"
  DOMAIN=$(house_endpoint)

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

house_check_host () {
  getent hosts "$(house_endpoint)"
}

house_undo_host () {
  IP_ADDR="127.0.0.1"
  DOMAIN=$(house_endpoint)
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

house_tunnel () {
  ssh -f -N -L 127.0.0.1:5439:"$(house_endpoint)":5439 \
    ubuntu@"$(house_instance)" -i ~/.ssh/orcahouse-mgmt \
    -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id %h'
}

house_tunnel_fg () {
  # keep tunnel in the foreground, ctrl+c to end the tunnel session
  ssh -v -N -L 127.0.0.1:5439:"$(house_endpoint)":5439 \
    ubuntu@"$(house_instance)" -i ~/.ssh/orcahouse-mgmt \
    -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id %h'
}

house_nc () {
  nc -vz 127.0.0.1 5439
}

house_status () {
  # ps aux | grep '[s]sh'
  # ps aux | grep '[o]rcahouse-mgmt'
  ps aux | grep '[o]pen-tunnel'
}

house_stop () {
  # kill <PID>
  pkill -f "open-tunnel"
}

house_forward () {
  aws ssm start-session \
    --target "$(house_instance)" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"portNumber\":[\"5439\"],\"localPortNumber\":[\"5439\"],\"host\":[\"$(house_endpoint)\"]}"
}

house_cred () {
  DBT_ENV_SECRET_HOST=$(house_endpoint)
  export DBT_ENV_SECRET_HOST
  export DBT_ENV_SECRET_USER="dbt" # pragma: allowlist secret
  env | grep DBT
}

house_clean () {
  unset DBT_ENV_SECRET_HOST DBT_ENV_SECRET_PASSWORD DBT_ENV_SECRET_USER
  env | grep DBT
}
