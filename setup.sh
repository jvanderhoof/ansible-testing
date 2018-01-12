#!/bin/bash -ex

function finish {
  echo 'Removing demo environment'
  echo '---'
  restore_conjurrc_and_netrc
  docker-compose down -v
}
# trap finish EXIT

function set_db_password {
  echo '--------- Set Password ------------'
  docker-compose run --rm -e CONJUR_AUTHN_API_KEY=$1 --entrypoint /bin/bash client -c "
    conjur variable values add db/password \"$(openssl rand -hex 12)\"
  "
}

function load_conjur_policies {
  echo '--------- Load Conjur Policy ------------'
  docker-compose run --rm -e CONJUR_AUTHN_API_KEY=$1 --entrypoint /bin/bash client -c "
    conjur policy load --replace root /src/policy/conjur.yml
    conjur policy load db /src/policy/db.yml
  "
}

function write_conjurrc {
  echo "---
account: demo-policy
plugins: []
appliance_url: http://localhost:8080" >> ~/.conjurrc
}

function write_netrc {
  echo "machine http://localhost:8080/authn
  login admin
  password $1" >> ~/.netrc
  chmod og-rw ~/.netrc
}

function backup_conjurrc_and_netrc {
  mv ~/.conjurrc ~/.conjurrc_bu
  mv ~/.netrc ~/.netrc_bu
}

function restore_conjurrc_and_netrc {
  rm -f ~/.conjurrc
  mv ~/.conjurrc_bu ~/.conjurrc
  rm -f ~/.netrc
  mv ~/.netrc_bu ~/.netrc
}

function run_test_playbook {
  # load Ansible from local project
  source ../ansible/hacking/env-setup

  # configure ~/.netrc & ~/.conjurrc
  backup_conjurrc_and_netrc
  write_conjurrc
  write_netrc $1

  # run playbook
  ansible-playbook -i "localhost," -vvv -c local ../ansible-testing/test-playbook.yml
}

function configure_conjur {
  load_conjur_policies $1
  set_db_password $1
}

function generate_tls {
  docker run --rm -it \
       -w /home -v $PWD/tls:/home \
       svagi/openssl req\
       -x509 \
       -nodes \
       -days 365 \
       -newkey rsa:2048 \
       -config /home/tls.conf \
       -extensions v3_ca \
       -keyout nginx.key \
       -out nginx.crt
}

function main {
  docker-compose up -d conjur client
  sleep 5

  api_key=$(docker-compose exec conjur rails r "print Credentials['demo-policy:user:admin'].api_key")
  configure_conjur $api_key
  run_test_playbook $api_key
}

main
