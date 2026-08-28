# Wireshark filters for SQL Server incidents

## Capture filters

Use capture filters when you know the SQL Server port in advance.

```text
tcp port 1433
```

For a custom SQL Server port:

```text
tcp port 1520
```

For two ports:

```text
tcp port 1520 or tcp port 1530
```

To limit capture to a server IP:

```text
host 10.10.10.20 and tcp port 1433
```

## Display filters

SQL Server traffic by TCP port:

```text
tcp.port == 1433
```

TCP SYN packets:

```text
tcp.flags.syn == 1 && tcp.flags.ack == 0
```

TCP resets:

```text
tcp.flags.reset == 1
```

TCP retransmissions:

```text
tcp.analysis.retransmission
```

Duplicate ACKs:

```text
tcp.analysis.duplicate_ack
```

TLS handshake:

```text
tls.handshake
```

TLS alerts:

```text
tls.alert_message
```

Traffic between a client and SQL Server:

```text
ip.addr == CLIENT_IP && ip.addr == SQL_SERVER_IP
```

Traffic between a client and SQL Server on a custom port:

```text
ip.addr == CLIENT_IP && ip.addr == SQL_SERVER_IP && tcp.port == SQL_PORT
```

## Pre-login handshake checklist

When troubleshooting `pre-login handshake` or intermittent connection timeouts, verify in this order:

1. Does DNS resolve the expected address?
2. Does TCP three-way handshake complete?
3. Are there retransmissions or resets before SQL Server responds?
4. Does TLS negotiation begin?
5. Is a TLS alert returned?
6. Does the client connect to the expected port?
7. Does the issue affect all clients or only one host/process?
8. Compare SSMS and PowerShell/.NET traffic from the same host.

A successful TCP connection does not prove that SQL Server login negotiation succeeds. `Test-NetConnection` validates network reachability; Wireshark helps identify what happens after TCP connects.
