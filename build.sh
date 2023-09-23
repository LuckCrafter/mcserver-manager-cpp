#!/bin/sh
cd $(dirname $(realpath $0))
mkdir -p build
g++ main.cpp -lcurl -o build/main