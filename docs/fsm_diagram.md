# eth_parser FSM Diagram

```
           +----------------+
           |                | <-------------+
           |   FSM_IDLE     |               |
           |                |               |
           +-------+--------+               |
                   |                        |
             tvalid & enable                |
                   |                        |
                   v                        |
           +----------------+               |
           |                |               |
           |  FSM_ETH_HDR   |               |
           |   (14 bytes)   |               |
           |                |               |
           +-------+--------+               |
                   |                        |
         ethertype == 0x0800                |
                   |                        |
                   v                        |
           +----------------+               |
           |                |               |
           |   FSM_IP_HDR   |               |
           |  (20-60 bytes) |               |
           |                |               |
           +-------+--------+               |
                   |                        |
             protocol == 17                 |
                   |                        |
                   v                        |
           +----------------+               |
           |                |               |
           |  FSM_UDP_HDR   |               |
           |   (8 bytes)    |               |
           |                |               |
           +-------+--------+               |
                   |                        |
           port == MAV_PORT                 |
                   |                        |
                   v                        |
           +----------------+               |
           |                |               |
           |  FSM_MAV_SYNC  |               |
           | (wait for 0xFD)|               |
           |                |               |
           +-------+--------+               |
                   |                        |
             data == 0xFD                   |
                   |                        |
                   v                        |
           +----------------+               |
           |                |               |
+--------> |  FSM_MAV_HDR   |               |
|          |   (9 bytes)    |               |
|          |                |               |
|          +-------+--------+               |
|                  |                        |
|                  v                        |
|          +----------------+               |
|          |                |               |
|          | FSM_MAV_PAYLOAD|               |
|          |  (var bytes)   |               |
|          |                |               |
|          +-------+--------+               |
|                  |                        |
|                  v                        |
|          +----------------+               |
|          |                |               |
|          |  FSM_FORWARD   |               |
|          | (until tlast)  |               |
|          |                |               |
|          +-------+--------+               |
|                  |                        |
|                  +------------------------+
|
|
+-------------------------------------------------+
|                                                 |
|                   FSM_DROP                      |
|                                                 |
| (entered from any state if check fails.         |
|  consumes bytes until tlast, then goes IDLE)    |
+-------------------------------------------------+
```

my supervisor asked for an FSM diagram. i drew this in text editor.
he sighed but accepted it.
