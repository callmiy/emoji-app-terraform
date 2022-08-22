cat <<EOF >>~/.ssh/config

Host ${host}
  HostName ${ip}
  Port 22
  User ${user}
  ForwardX11 yes
  RequestTTY yes
  IdentityFile ${identityfile}
  StrictHostKeyChecking no
EOF
