#!/bin/bash
set -e

echo "ApplicationStart - starting webapp service"

systemctl daemon-reload
systemctl start webapp

echo "Waiting for 5 seconds..."
sleep 5

if systemctl is-active --quiet webapp; then
  echo "webapp service is running"
else
  echo "ERROR: webapp failed to start"
  systemctl status webapp --no-pager
  exit 1
fi

echo "ApplicationStart completed"
