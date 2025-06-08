#!/bin/bash
set -e

attachment="$1"
subject="BSO Scan Report $(basename $attachment)"
body="W załączniku raport z automatycznego skanowania sieci."

# msmtp korzysta z konfiguracji w ~/.msmtprc
echo -e "Subject: ${subject}\n\n${body}" | msmtp --attach="$attachment" "${EMAIL_TO}"
