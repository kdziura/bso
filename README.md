# BSO - Greenbone-based Scanner
**Scanner made for Debian-based systems**

Based on Greenbone Community Containers - https://greenbone.github.io/docs/latest/22.4/container/index.html

One line install: 
``` 
curl -sSL https://raw.githubusercontent.com/kdziura/bso/main/install.sh | bash
``` 

If instalation fails, run the following commands: 

sudo apt update 
sudo apt install docker-compose-plugin

To start a scan manually, run ` ./bso-main/automation/scripts/run_full_scan.sh `

Don't start a scan until synchronization is complete!

You can check it's status at this URL: 127.0.0.1:9392/feedstatus

To enable cron (automatic updates and scans) run ` ./automation/scripts/configure_cron.sh `