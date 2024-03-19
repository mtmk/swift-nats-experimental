# swift-nats-experimental

How to run the benchmarks:

* download `nats-server` (single binary with no dependencies) https://github.com/nats-io/nats-server/releases/latest
* download `nats` command line client (single binary with no dependencies) https://github.com/nats-io/natscli/releases/latest

1) Run nats-server on one terminal
```
nats-server
```

2) Start nats benchmark subscription on another terminal
```
nats bench x --sub 1 --msgs 100000
```

3) Run the example
```
swift run -c release example
```

4) Compare to nats bench itself (essentially the Go client)
```
nats bench x --pub 1 --msgs 100000
```
