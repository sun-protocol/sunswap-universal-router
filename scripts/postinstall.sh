#!/bin/bash
set -e  

echo "Cloning v4-core..."
git clone --branch v1.0.0 git@g.teches.link:sunio/exchange/contract/v4-core.git ./lib/v4-core

echo "Cloning sunswap-v4-periphery..."
git clone --branch v1.0.0 git@g.teches.link:sunio/exchange/contract/sunswap-v4-periphery.git ./lib/sunswap-v4-periphery

echo "Cloning sunswap-permit2..."
git clone --branch v1.0.0 git@g.teches.link:sunio/exchange/contract/sunswap-permit2.git ./lib/sunswap-permit2

echo "Cloning forge-std..."
git clone --branch v1.12.0 --depth 1 https://github.com/foundry-rs/forge-std ./lib/forge-std

echo "Cloning openzeppelin-contracts..."
git clone --branch v5.5.0 --depth 1 https://github.com/OpenZeppelin/openzeppelin-contracts ./lib/openzeppelin-contracts

echo "Cloning solmate..."
git clone https://github.com/transmissions11/solmate ./lib/solmate
cd lib/solmate
git checkout 89365b880c4f3c786bdd453d4b8e8fe410344a69
cd ../../

echo "Cloning pancake-create3-factory..."
git clone https://github.com/pancakeswap/pancake-create3-factory ./lib/pancake-create3-factory
cd lib/pancake-create3-factory
git checkout 84290a60b57a934390b263007d5b4fab24c04010
cd ../../

echo "✅ All repositories cloned successfully."
