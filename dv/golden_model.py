#!/usr/bin/env python3
"""
Hardware-Accelerated Packet Classification Engine
Golden Reference Model

This script serves as the behavioral oracle for the RTL datapath. 
It processes a PCAP file (or generated traffic), applies the exact 
firewall rules configured in the hardware, and outputs the expected 
telemetry statistics (Packet counts, drops, bytes, protocols).

The DV testbench compares hardware AXI-Lite reads against this output.
"""

import sys
try:
    from scapy.all import rdpcap, IP, TCP, UDP, ICMP
except ImportError:
    print("Scapy not found. Install with: pip install scapy")
    sys.exit(1)

class GoldenFirewall:
    def __init__(self):
        # Expected Hardware Telemetry
        self.stat_rx_pkts = 0
        self.stat_tx_pkts = 0
        self.stat_drops = 0
        self.stat_rx_bytes = 0
        self.stat_tx_bytes = 0
        self.stat_tcp = 0
        self.stat_udp = 0
        self.stat_icmp = 0
        self.stat_parse_errors = 0
        
        # Simple Mock Rule Table (Normally synchronized with RTL AXI-Lite writes)
        self.rules = []

    def load_pcap(self, filepath):
        print(f"Loading PCAP: {filepath}")
        packets = rdpcap(filepath)
        for pkt in packets:
            self.process_packet(pkt)
            
    def process_packet(self, pkt):
        self.stat_rx_pkts += 1
        self.stat_rx_bytes += len(pkt)
        
        if not IP in pkt:
            self.stat_parse_errors += 1
            self.stat_drops += 1
            return
            
        ip_layer = pkt[IP]
        
        if TCP in pkt:
            self.stat_tcp += 1
        elif UDP in pkt:
            self.stat_udp += 1
        elif ICMP in pkt:
            self.stat_icmp += 1
            
        # Simulate Rule Match (Default action: Forward)
        action_forward = True
        
        # Evaluate rules (Simplified for oracle)
        for rule in self.rules:
            if ip_layer.src == rule['src'] and ip_layer.dst == rule['dst']:
                action_forward = rule['action']
                break
                
        if action_forward:
            self.stat_tx_pkts += 1
            self.stat_tx_bytes += len(pkt)
        else:
            self.stat_drops += 1

    def print_expected_statistics(self):
        print("\n=====================================")
        print("    GOLDEN ORACLE TELEMETRY OUTPUT   ")
        print("=====================================")
        print(f"RX Packets    : {self.stat_rx_pkts}")
        print(f"TX Packets    : {self.stat_tx_pkts}")
        print(f"Dropped       : {self.stat_drops}")
        print(f"Parse Errors  : {self.stat_parse_errors}")
        print("-------------------------------------")
        print(f"TCP Packets   : {self.stat_tcp}")
        print(f"UDP Packets   : {self.stat_udp}")
        print(f"ICMP Packets  : {self.stat_icmp}")
        print("-------------------------------------")
        print(f"RX Bytes      : {self.stat_rx_bytes}")
        print(f"TX Bytes      : {self.stat_tx_bytes}")
        print("=====================================\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python golden_model.py <traffic.pcap>")
        sys.exit(1)
        
    fw = GoldenFirewall()
    
    # In a real DV environment, rules would be parsed from a config file shared with the SV testbench.
    fw.rules.append({'src': '192.168.1.100', 'dst': '10.0.0.1', 'action': False}) # Drop this specific flow
    
    fw.load_pcap(sys.argv[1])
    fw.print_expected_statistics()
