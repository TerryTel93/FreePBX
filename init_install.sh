#!/bin/bash

# Start MariaDB
service mariadb start

# Start Asterisk
./start_asterisk start

# Run installation script
./install -n

if [ $? -eq 1 ]; then
  fwconsole ma installall
  fwconsole reload
  fwconsole restart
  exit 0
else
  echo "Installation failed with code: $?"
  exit $?
fi
