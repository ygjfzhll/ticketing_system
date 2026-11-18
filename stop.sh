#!/bin/bash

kill -9 `ps -ef | grep node | grep -v grep | grep -v node_expor | awk '{print $2}'`
