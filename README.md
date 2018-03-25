# Introduction

IOHK test task - send messages from nodes generating random numbers from 0 to 1 to other nodes. All nodes print the formula ```(length msgs, sum $ zipWith (\i msg -> i * msg) [1..] msgs)```  

# Running

```bash
$ cabal configure --enable-tests
$ cabal install   --only-dependencies
$ cabal run    -- --help
```

# Configuration file

The configuration file is found at: ```config/nodes.txt```
The file can also be specified with command line option.

# TODO

Reduce the number of messages sent - try to reduce the number of edges between nodes.
