#!/bin/bash


#### Configuration options #############################################

# One Docker container will be configured for each IP address in $ips
subnet="172.13.0.0/24"
number_of_node=7

# Docker image name
image=kambit/quorum
istanbul_image=kambit/istanbul-tools

uid=`id -u`
gid=`id -g`
pwd=`pwd`

if [[ $number_of_node < 02 ]]
then
    echo "ERROR: There must be more than one node IP address."
    exit 1
fi

########################################################################


#### Create directories for each node's configuration ##################

echo '[1] Configuring for '$number_of_node' nodes'

n=1
while (( $n<=$number_of_node ))
do
    qd=qdata_$n
    mkdir -p $qd/tm
    mkdir -p $qd/dd/{keystore,geth}

    let n++
done


#### Create nodekey, static-nodes.json and genesis.json template file #######################

echo '[2] Creating static-nodes.json, nodekey and genesis.json template'

# create static-nodes.json, nodekey and genesis.json with istanbul
istanbul_dir="istanbul_dir"
mkdir $istanbul_dir
cd $istanbul_dir
# istanbul setup --num $number_of_node --nodes --quorum --save --verbose

docker run -v $pwd/$istanbul_dir:/istanbul-tools-tmp $istanbul_image /bin/sh -c "cd /istanbul-tools-tmp && istanbul setup --num $number_of_node --nodes --quorum --save --verbose"

#### finish static-nodes.json #######################
echo '[3] finish static-nodes.json.'
# replace item in static-nodes.json

n=1
comm=
while (( $n<=$number_of_node ))
do  
    comm+='-e '$[$n+1]'s/0.0.0.0:30303?discport=0/172.16.239.'$[$n+10]':21000?discport=0\&raftport='$[$c+50400]'/g '
    let n++
done
sed -in-place $comm static-nodes.json 

cd ../

### Create accounts and genesis.json file #######################

echo '[4] Creating Ether accounts and genesis.json'

cat > genesis.json <<EOF
{
  "alloc": {
EOF


n=1
while (( $n<=$number_of_node ))
do
    qd=qdata_$n

    # Generate an Ether account for the node
    touch $qd/passwords.txt
    account=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/geth --datadir=/qdata/dd --password /qdata/passwords.txt account new | cut -c 11-50`
    
    sep=`[[ $n != $number_of_node ]] && echo ","`
    cat >> genesis.json <<EOF
    "0x${account}": {
      "balance": "1000000000000000000000000000"
    }${sep}
EOF

    let n++
done

cat >> genesis.json <<EOF
  },
EOF

if [ "$QUORUM_CONSENSUS" == "raft" ];
then
cat >> genesis.json <<EOF
  "coinbase": "0x0000000000000000000000000000000000000000",
  "config": {
    "homesteadBlock": 0,
    "byzantiumBlock": 0,
    "chainId": 10,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "eip158Block": 0,
    "isQuorum": true
  },
  "difficulty": "0x0",
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "gasLimit": "0xFFFFFFFFFFFFFFFF",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578",
  "nonce": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x00"
}
EOF
else
# add template part in to genesis.json
end_num=$(sed -n '$=' istanbul_dir/genesis.json)
begin_num=$(sed -n '/alloc/=' istanbul_dir/genesis.json)

sed "${begin_num},$[${end_num}-4]d" istanbul_dir/genesis.json | sed -n '2,$p' >> genesis.json
fi

#### distribute nodekey, static-nodes.json and genesis.json file #######################

echo '[5] distribute nodekey, static-nodes.json and genesis.json file'

n=1
while (( $n<=$number_of_node ))
do
    qd=qdata_$n/dd
    cp $istanbul_dir/$[$n-1]/nodekey $qd/geth/nodekey
    cp $istanbul_dir/static-nodes.json $qd/static-nodes.json
    cp $istanbul_dir/static-nodes.json $qd/permissioned-nodes.json
    cp genesis.json $qd/genesis.json

    let n++
done



#### Complete each node's configuration ################################

echo '[6] Creating Quorum keys and finishing configuration.'

n=1
while (( $n<=$number_of_node ))
do
    qd=qdata_$n

    # Generate Quorum-related keys (used by Constellation)
    # docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/constellation-node  --generatekeys=/qdata/tm/tm < /dev/null > /dev/null
    constellation-node  --generatekeys=$qd/tm/tm < /dev/null > /dev/null
    constellation-node  --generatekeys=$qd/tm/tma < /dev/null > /dev/null
    # docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/constellation-node  --generatekeys=/qdata/tm/tma < /dev/null > /dev/null
    echo 'Node '$n' public key: '`cat $qd/tm/tm.pub`

    let n++
done

sudo rm -rf $istanbul_dir
sudo rm genesis.json
# sudo docker rm -f $(sudo docker ps -qa)


#### Create the docker-compose.yml file ####################################

echo '[7] Create the docker-compose.yml file'

cat > docker-compose.yml <<EOF
version: "3.6"
x-quorum-def:
  &quorum-def
  restart: "on-failure"
  image: "\${QUORUM_DOCKER_IMAGE:-quorumengineering/quorum:2.3.0}"
  expose:
    - "21000"
    - "50400"
  healthcheck:
    test: ["CMD", "wget", "--spider", "--proxy", "off", "http://localhost:8545"]
    interval: 3s
    timeout: 3s
    retries: 10
    start_period: 5s
  labels:
    com.quorum.consensus: \${QUORUM_CONSENSUS:-istanbul}
  entrypoint:
    - /bin/sh
    - -c
    - |
      UDS_WAIT=10
      for i in \$\$(seq 1 100)
      do
        set -e
        if [ -S \$\${PRIVATE_CONFIG} ] && \\
          [ "I'm up!" == "\$\$(wget --timeout \$\${UDS_WAIT} -qO- --proxy off 172.16.239.\$\$((NODE_ID+100)):9000/upcheck)" ];
        then break
        else
          echo "Sleep \$\${UDS_WAIT} seconds. Waiting for TxManager."
          sleep \$\${UDS_WAIT}
        fi
      done
      DDIR=/qdata/dd
      DDDIR=/qqdata/dd
      rm -rf \$\${DDIR}
      mkdir -p \$\${DDIR}/keystore
      mkdir -p \$\${DDIR}/geth
      cp \$\${DDDIR}/geth/nodekey \$\${DDIR}/geth/nodekey
      cp \$\${DDDIR}/keystore/* \$\${DDIR}/keystore/
      cp \$\${DDDIR}/permissioned-nodes.json \$\${DDIR}/permissioned-nodes.json
      cp \$\${DDDIR}/static-nodes.json \$\${DDIR}/static-nodes.json
      cp qqdata/passwords.txt \$\${DDIR}/passwords.txt
      cat \$\${DDIR}/static-nodes.json
      GENESIS_FILE=\$\${DDDIR}"/genesis.json"
      NETWORK_ID=\$\$(cat \$\${GENESIS_FILE} | grep chainId | awk -F " " '{print \$\$2}' | awk -F "," '{print \$\$1}')
      GETH_ARGS_raft="--raft --raftport 50400"
      GETH_ARGS_istanbul="--emitcheckpoints --istanbul.blockperiod 1 --mine --minerthreads 1 --syncmode full"
      geth --datadir \$\${DDIR} init \$\${GENESIS_FILE}
      nohup geth \\
        --identity node\$\${NODE_ID}-\${QUORUM_CONSENSUS:-istanbul} \\
        --datadir \$\${DDIR} \\
        --permissioned \\
        --nodiscover \\
        --verbosity 5 \\
        --networkid \$\${NETWORK_ID} \\
        --rpc \\
        --rpcaddr 0.0.0.0 \\
        --rpcport 8545 \\
        --rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum,\${QUORUM_CONSENSUS:-istanbul} \\
        --port 21000 \\
        --unlock 0 \\
        --password \$\${DDIR}/passwords.txt \\
        --miner.gaslimit 18446744073709551615 \\
        --miner.gastarget 18446744073709551615 \\
        \$\${GETH_ARGS_\${QUORUM_CONSENSUS:-istanbul}} \\
        2>>\$\${DDDIR}/geth.log
x-tx-manager-def:
  &tx-manager-def
  image: "\${QUORUM_TX_MANAGER_DOCKER_IMAGE:-quorumengineering/tessera:0.10.0}"
  expose:
    - "9000"
    - "9080"
  restart: "no"
  healthcheck:
    test: ["CMD-SHELL", "[ -S /qdata/tm/tm.ipc ] || exit 1"]
    interval: 3s
    timeout: 3s
    retries: 20
    start_period: 5s
  entrypoint:
    - /bin/sh
    - -c
    - |
      DDIR=/qdata/tm
      DDDIR=/qqdata/tm
      rm -rf \$\${DDIR}
      mkdir -p \$\${DDIR}
      DOCKER_IMAGE="\${QUORUM_TX_MANAGER_DOCKER_IMAGE:-quorumengineering/tessera:0.10.0}"
      TX_MANAGER=\$\$(echo \$\${DOCKER_IMAGE} | sed 's/^.*\/\(.*\):.*\$\$/\1/g')
      echo "TxManager: \$\${TX_MANAGER}"
      case \$\${TX_MANAGER}
      in
        tessera)
          cp \$\${DDDIR}/tm.pub \$\${DDIR}/tm.pub
          cp \$\${DDDIR}/tm.key \$\${DDIR}/tm.key
          #extract the tessera version from the jar
          TESSERA_VERSION=\$\$(unzip -p /tessera/tessera-app.jar META-INF/MANIFEST.MF | grep Tessera-Version | cut -d" " -f2)
          echo "Tessera version (extracted from manifest file): \$\${TESSERA_VERSION}"
          # sorting versions to target correct configuration
          V08=\$\$(echo -e "0.8\n\$\${TESSERA_VERSION}" | sort -n -r -t '.' -k 1,1 -k 2,2 | head -n1)
          V09AndAbove=\$\$(echo -e "0.9\n\$\${TESSERA_VERSION}" | sort -n -r -t '.' -k 1,1 -k 2,2 | head -n1)
          TESSERA_CONFIG_TYPE=
          case "\$\${TESSERA_VERSION}" in
              "\$\${V09AndAbove}")
                  TESSERA_CONFIG_TYPE=""
                  ;;
          esac

          echo Config type \$\${TESSERA_CONFIG_TYPE}

          #generating the two config flavors
          cat <<EOF > \$\${DDIR}/tessera-config.json
          {
            "useWhiteList": false,
            "jdbc": {
              "username": "sa",
              "password": "",
              "url": "jdbc:h2:./\$\${DDIR}/db;MODE=Oracle;TRACE_LEVEL_SYSTEM_OUT=0",
              "autoCreateTables": true
            },
            "serverConfigs":[
            {
              "app":"ThirdParty",
              "enabled": true,
              "serverAddress": "http://\$\$(hostname -i):9080",
              "communicationType" : "REST"
            },
            {
              "app":"Q2T",
              "enabled": true,
              "serverAddress": "unix:\$\${DDIR}/tm.ipc",
              "communicationType" : "REST"
            },
            {
              "app":"P2P",
              "enabled": true,
              "serverAddress": "http://\$\$(hostname -i):9000",
              "sslConfig": {
                "tls": "OFF"
              },
              "communicationType" : "REST"
            }
            ],
            "peer": [
EOF

n=1
while (( $n<=$number_of_node ))
do  
    sep=`[[ $n != $number_of_node ]] && echo ","`
    cat >> docker-compose.yml <<EOF
                {
                    "url": "http://txmanager$n:9000"
                }${sep}
EOF

    let n++
done


cat >> docker-compose.yml <<EOF
              ],
              "keys": {
                  "passwords": [],
                  "keyData": [
                      {
                          "config": \$\$(cat \$\${DDIR}/tm.key),
                          "publicKey": "\$\$(cat \$\${DDIR}/tm.pub)"
                      }
                  ]
              },
              "alwaysSendTo": []
          }
      EOF
          cat \$\${DDIR}/tessera-config\$\${TESSERA_CONFIG_TYPE}.json
          java -Xms128M -Xmx128M -jar /tessera/tessera-app.jar -configfile \$\${DDIR}/tessera-config\$\${TESSERA_CONFIG_TYPE}.json
          ;;
        constellation)
          echo "socket=\"\$\${DDIR}/tm.ipc\"\npublickeys=[\"/examples/keys/tm\$\${NODE_ID}.pub\"]\n" > \$\${DDIR}/tm.conf
          constellation-node \\
            --url=http://\$\$(hostname -i):9000/ \\
            --port=9000 \\
            --socket=\$\${DDIR}/tm.ipc \\
            --othernodes=http://172.16.239.101:9000/,http://172.16.239.102:9000/,http://172.16.239.103:9000/,http://172.16.239.104:9000/,http://172.16.239.105:9000/ \\
            --publickeys=/examples/keys/tm\$\${NODE_ID}.pub \\
            --privatekeys=/examples/keys/tm\$\${NODE_ID}.key \\
            --storage=\$\${DDIR} \\
            --verbosity=4
          ;;
        *)
          echo "Invalid Transaction Manager"
          exit 1
          ;;
      esac
services:
EOF

n=1
while (( $n<=$number_of_node ))
do  
    cat >> docker-compose.yml <<EOF
  node$n:
    << : *quorum-def
    hostname: node$n
    ports:
      - "$[$n-1+22000]:8545"
    volumes:
      - vol$n:/qdata
      - './qdata_$n:/qqdata'
    depends_on:
      - txmanager$n
    environment:
      - PRIVATE_CONFIG=/qdata/tm/tm.ipc
      - NODE_ID=$n
    networks:
      quorum-examples-net:
        ipv4_address: 172.16.239.$[$n+10]
  txmanager$n:
    << : *tx-manager-def
    hostname: txmanager$n
    ports:
      - "$[$n+9080]:9080"
    volumes:
      - vol$n:/qdata
      - './qdata_$n:/qqdata'
    networks:
      quorum-examples-net:
        ipv4_address: 172.16.239.$[$n+100]
    environment:
      - NODE_ID=$n
EOF

    let n++
done

cat >> docker-compose.yml <<EOF
networks:
  quorum-examples-net:
    driver: bridge
    ipam:
      driver: default
      config:
      - subnet: 172.16.239.0/24
volumes:
EOF

n=1
while (( $n<=$number_of_node ))
do  
    cat >> docker-compose.yml <<EOF
  "vol$n":
EOF

    let n++
done