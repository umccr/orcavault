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
  ORCAVAULT_SCHEMA=${ORCAVAULT_SCHEMA:-$(house_schema)} || return
  export ORCAVAULT_SCHEMA
  export DBT_DEFER=true DBT_STATE=target/upstream
  env | grep -E 'DBT|ORCAVAULT'
}

house_schema () {
  # dev_<your AWS SSO username>, e.g. .../AWSReservedSSO_<role>/marko.malenic@<domain> is dev_marko_malenic
  local arn
  arn=$(aws sts get-caller-identity --output text --query Arn) || return
  echo "dev_${arn##*/}" | sed 's|@.*||' | tr -c 'a-zA-Z0-9\n' '_' | tr 'A-Z' 'a-z'
}

house_clean () {
  unset DBT_ENV_SECRET_HOST DBT_ENV_SECRET_PASSWORD DBT_ENV_SECRET_USER DBT_DEFER DBT_STATE
  env | grep DBT
}

house_up () {
  house_key && house_host || return
  house_status > /dev/null || house_tunnel || return
  house_nc
  house_cred
}

house_down () {
  house_stop
  house_clean
}

house_upstream () {
  echo "s3://orcavault-run-dev-results-$(aws sts get-caller-identity --output text --query Account)-ap-southeast-2-an/state/manifest.json"
}

dbt_defer () {
  # Fetch what the dev daily run built, then rebuild changes on top of it in your personal schema, reading the rest from dev.
  aws s3 cp "$(house_upstream)" target/upstream/manifest.json \
    && dbt build --select state:modified+ --defer --favor-state --state target/upstream --full-refresh "$@"
}

dbt_clone () {
  # Same as dbt_defer, after making a view of dev's table in your personal schema for every model you haven't changed.
  aws s3 cp "$(house_upstream)" target/upstream/manifest.json \
    && dbt clone --exclude state:modified+ --state target/upstream --full-refresh \
    && dbt build --select state:modified+ --defer --favor-state --state target/upstream --full-refresh "$@"
}

dbt_status () {
  # Similar to git status: what you've changed since the last dbt_defer or dbt_clone, and whether dev has run since.
  aws s3 cp --quiet "$(house_upstream)" target/upstream/latest.json \
    && { cmp -s target/upstream/latest.json target/upstream/manifest.json \
      || echo "dev has run since your last dbt_defer or dbt_clone, run one of them again before you build"; }
  dbt ls --select state:modified+ --state target/upstream --resource-type model --resource-type seed "$@"
}

dbt_drop () {
  # Similar to deleting a git branch: drop every schema of your personal schema. Preview with --args '{dry_run: true}'.
  dbt run-operation drop_personal_schemas "$@"
}
