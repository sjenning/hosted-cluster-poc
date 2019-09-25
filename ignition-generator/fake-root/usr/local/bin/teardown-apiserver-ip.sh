#!/usr/bin/env bash
set -x
ip addr delete 172.20.0.1/32 dev lo
ip route del 172.20.0.1/32 dev lo scope link src 172.20.0.1
