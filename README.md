# Set N Quorum Nodes with docker(raft and istanbul)
Run a bunch of Quorum nodes, each in a separate Docker container.

This script can setup maximum 99 Quorum Nodes in one instance.

This is simply a learning exercise for configuring Quorum networks. Probably best not used in a production environment.



# Quickstart(default is istanbul)

```
git clone https://github.com/kambit/quorum_easy_setup.git
cd quorum_easy_setup
sudo ./setup.sh
sudo docker-compose up -d
```

**Notice:** more nodes need wait more time until all nodes setup completely. 



# Test

```
geth attach http://127.0.0.1:22000
```

or

```
docker exec -it ttt_node1_1 geth attach /qdata/dd/geth.ipc
```



# Modify number of Quorum nudes

Edit setup.sh at line 8.

```
number_of_node=5
```

change any number you want. The maximum is 99.

**Notice:** Consider memory capacity !!!

#Select consensus algorithm with raft or istanbul

### start with raft

```
QUORUM_CONSENSUS=raft sudo ./setup.sh
QUORUM_CONSENSUS=raft docker-compose up -d
```

### start with istanbul

```
QUORUM_CONSENSUS=istanbul sudo ./setup.sh
QUORUM_CONSENSUS=istanbul docker-compose up -d
```



#Clean

```
./cleaner.sh
```

**Notice:** This script will ***shutdown*** and ***remove*** all containers.



#Easy test env

Re-setup.sh is an easily clean and setup Quorum nodes script.

**Recommend:** Test only. 

```
./re-setup.sh
```



# Basement

These scripts build on [quorum-docker-Nnodes](<https://github.com/kambit/quorum-docker-Nnodes>) and [quorum-examples](<https://github.com/kambit/quorum-examples>). 