#!/bin/bash

# VirtualBox and Vagrant are required for this kind of deployment
#	- VirtualBox: https://www.virtualbox.org/wiki/Downloads
#	- Vagrant: https://www.vagrantup.com/downloads.html

# The latest version contains kubeflow 0.7

vagrant init arrikto/minikf
vagrant up
