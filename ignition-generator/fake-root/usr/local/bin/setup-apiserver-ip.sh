#!/usr/bin/env bash
set -x
ip addr add 172.20.0.1/32 brd 172.20.0.1 scope host dev lo
ip route add 172.20.0.1/32 dev lo scope link src 172.20.0.1
