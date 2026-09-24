#!/bin/sh

## hyphop ##

[ -x /bin/opkg ] && {
alias opkf='opkg --force-space --force-checksum --force-depends'
alias opkd='opkg --force-space --nodeps'
}

export TERM=xterm
