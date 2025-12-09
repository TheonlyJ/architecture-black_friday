#!/bin/bash

set -e

echo "Starting MongoDB sharded cluster initialization..."

# Function to wait for MongoDB instance to be ready
wait_for_mongo() {
    local host=$1
    local port=$2
    local max_attempts=30
    local attempt=1

    echo "Waiting for MongoDB at $host:$port to be ready..."

    while [ $attempt -le $max_attempts ]; do
        if mongosh --host $host --port $port --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
            echo "MongoDB at $host:$port is ready!"
            return 0
        fi

        echo "Attempt $attempt/$max_attempts: MongoDB at $host:$port not ready yet..."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "ERROR: MongoDB at $host:$port failed to become ready after $max_attempts attempts"
    return 1
}

# Function to initialize replica set
init_replica_set() {
    local host=$1
    local port=$2
    local rs_name=$3
    local is_configsvr=$4

    echo "Initializing replica set: $rs_name at $host:$port"

    wait_for_mongo $host $port

    # Check if replica set is already initialized
    if mongosh --host $host --port $port --eval "rs.status()" --quiet > /dev/null 2>&1; then
        echo "Replica set $rs_name is already initialized"
        return 0
    fi

    # Initialize replica set
    if [ "$is_configsvr" = "true" ]; then
        mongosh --host $host --port $port --eval "
            rs.initiate({
                _id: '$rs_name',
                configsvr: true,
                members: [
                    { _id: 0, host: '$host:$port' }
                ]
            })
        "
    else
        mongosh --host $host --port $port --eval "
            rs.initiate({
                _id: '$rs_name',
                members: [
                    { _id: 0, host: '$host:$port' }
                ]
            })
        "
    fi

    echo "Replica set $rs_name initialization command sent"

    # Wait for primary election
    echo "Waiting for $rs_name to elect primary..."
    local wait_attempt=1
    while [ $wait_attempt -le 30 ]; do
        if mongosh --host $host --port $port --eval "db.isMaster().ismaster" --quiet | grep -q "true"; then
            echo "$rs_name primary elected successfully!"
            break
        fi
        echo "Waiting for $rs_name primary election... ($wait_attempt/30)"
        sleep 2
        wait_attempt=$((wait_attempt + 1))
    done

    echo "Adding extra replicas for $rs_name..."

    if [[ "$rs_name" == "shard-1" ]]; then
        mongosh --host $host --port $port --eval "
            cfg = rs.conf();
            cfg.members.push({ _id: 1, host: 'shard-1-2:27018' });
            cfg.members.push({ _id: 2, host: 'shard-1-3:27018' });
            rs.reconfig(cfg, { force: true });
        "
    fi

    if [[ "$rs_name" == "shard-2" ]]; then
        mongosh --host $host --port $port --eval "
            cfg = rs.conf();
            cfg.members.push({ _id: 1, host: 'shard-2-2:27019' });
            cfg.members.push({ _id: 2, host: 'shard-2-3:27019' });
            rs.reconfig(cfg, { force: true });
        "
    fi
}

# Function to add shards via router
add_shards() {
    local router_host=$1
    local router_port=$2

    echo "Adding shards via router $router_host:$router_port"

    wait_for_mongo $router_host $router_port

    # Add shard-1
    if mongosh --host $router_host --port $router_port --eval "sh.status()" --quiet | grep -q "shard-1"; then
        echo "Shard-1 already added"
    else
        echo "Adding shard-1..."
        mongosh --host $router_host --port $router_port --eval "
            sh.addShard('shard-1/shard-1-1:27018')
        "
    fi

    # Add shard-2
    if mongosh --host $router_host --port $router_port --eval "sh.status()" --quiet | grep -q "shard-2"; then
        echo "Shard-2 already added"
    else
        echo "Adding shard-2..."
        mongosh --host $router_host --port $router_port --eval "
            sh.addShard('shard-2/shard-2-1:27019')
        "
    fi
}

fill_data() {
  local router_host=$1
  local router_port=$2

    wait_for_mongo $router_host $router_port
    # Enable sharding and create collection
    echo "Setting up sharding for database... $router_host $router_port"
    mongosh --host $router_host --port $router_port --eval "
        sh.enableSharding('somedb');
        sh.shardCollection('somedb.helloDoc', { 'name': 'hashed' });
        const db = new Mongo('mongodb://router-1:27020').getDB(\"somedb\");
        for(var i = 0; i < 1000; i++) {
         db.helloDoc.insertOne({age:i, name:\"ly\"+i});}
        print('Sharding setup completed successfully!');
    "
    echo "Sharding configuration completed via $router_host:$router_port"

}

# Main initialization sequence
echo "=== Step 1: Initializing Config Server ==="
init_replica_set "configSrv" "27017" "config_server" "true"

echo "=== Step 2: Initializing Shards ==="
init_replica_set "shard-1-1" "27018" "shard-1" "false"
init_replica_set "shard-2-1" "27019" "shard-2" "false"

# Wait for shards to stabilize
echo "Waiting for shards to stabilize..."
sleep 10

echo "=== Step 3: Starting Router Configuration ==="
wait_for_mongo "router-1" "27020"
wait_for_mongo "router-2" "27021"

echo "=== Step 4: Configuring Sharding ==="
add_shards "router-1" "27020"
add_shards "router-2" "27021"

echo "=== Step 4.5: DATA ==="
fill_data "router-1" "27020"

echo "=== Step 5: Verifying Cluster ==="
mongosh --host router-1 --port 27020 --eval "
print('=== Cluster Status ===');
sh.status();
const db = new Mongo('mongodb://router-1:27020').getDB(\"somedb\");

print('\\n=== Database Info ===');
db.adminCommand('listDatabases');

print('\\n=== Shard Distribution ===');
db.helloDoc.getShardDistribution();
"

echo "=== MongoDB Sharded Cluster Initialization COMPLETED ==="
