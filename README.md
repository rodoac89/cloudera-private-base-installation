# Cloudera Private Cloud Base
This repo follows installation's steps documented on official Cloudera Documentation https://docs.cloudera.com/cdp-private-cloud-base/7.3.1/cdp-private-cloud-base-installation/topics/cdpdc-installation.html

## Script

Here you will find a script that will help you setup your Bare Metal clusters for Cloudera On Premises using Postgresql 17, OpenJDK 17, Python 3.8 and Active Directory

## Pre-requisities

1. You need to acquire a valid license for Cloudera on Premises that you can get here [Cloudera main page](https://www.cloudera.com/)

2. Repository link with the user and pass provided by cloudera Eg: `https://[**username**]:[**password**]@archive.cloudera.com/p/cm7/[**Cloudera Manager version**]/redhat[**version number**]/yum/cloudera-manager.repo` this will be required during installation 

3. An **Active Directory** service running and their DNS IPs (these Ips will be required during installation)

## Execution

1. Upload the script `setup-cloudera-manager.sh` to home's user

2. Run `sudo chmod +x setup-cloudera-manager.sh` for add execution permission to the script

3. Run `sudo ./setup-cloudera-manager.sh` and follow the instructions 


 
