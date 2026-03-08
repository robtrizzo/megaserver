#!/bin/sh
# Load /app/.env but do not overwrite variables already set.
if [ -f /app/.env ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      ''|\#*) ;;
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        eval "current=\${${key}:+set}"
        if [ -z "$current" ]; then
          export "$key=$value"
        fi
        ;;
    esac
  done < /app/.env
fi
exec "$@"