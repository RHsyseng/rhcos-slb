#!/bin/bash

set -xe

n=0
until [ "$n" -ge 5 ]
do
   $@ && break
   n=$((n+1)) 
done
