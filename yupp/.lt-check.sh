#!/bin/sh
df -h 2>&1 | grep -v -E "tmpfs|shm|overlay" | head
docker system df 2>&1
