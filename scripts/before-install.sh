#!/bin/bash
set -e

echo "BeforeInstall - stopping webapp service if it exists"

if systemctl list-units --full -all | grep -q "webapp.service"; then
  if systemctl is-active --quiet webapp; then
    echo "Stopping webapp service"
    systemctl stop webapp
  else
    echo "webapp service is not running"
  fi
else
  echo "webapp service does not exist yet"
fi

echo "Ensuring /var/www/WebApp exists"
mkdir -p /var/www/WebApp

echo "BeforeInstall completed"
