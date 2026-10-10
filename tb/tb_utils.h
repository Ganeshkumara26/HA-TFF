/*
 * tb_utils.h - utilities for packet generation in Verilator testbenches
 *
 * sept 25, 2026
 *
 * my supervisor said my "sunshine testbench" (tb_basic.sv) was useless
 * because it only tested the happy path. he told me to write C++ testbenches
 * using Verilator so i can use actual programming constructs to generate
 * constrained-random packets.
 *
 * this file contains the PacketBuilder class. it generates raw byte vectors
 * representing Ethernet/IP/UDP/MAVLink packets. i can easily corrupt CRCs,
 * truncate packets, or send non-IPv4 traffic.
 *
 * the CRC logic here is borrowed directly from my edp-core C project.
 * finally that code is useful again.
 */

#pragma once

#include <vector>
#include <cstdint>
#include <random>
#include <iostream>

// CRC-16/MCRF4XX from edp-core
inline uint16_t crc_accumulate(uint8_t data, uint16_t crcAccum) {
    uint8_t tmp = data ^ (uint8_t)(crcAccum & 0xff);
    tmp ^= (tmp << 4);
    return (crcAccum >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4);
}

// CRC_EXTRA lookup
inline uint8_t crc_extra(uint32_t msgid) {
    switch (msgid) {
        case 0:   return 50;   // HEARTBEAT
        case 1:   return 124;  // SYS_STATUS
        case 24:  return 24;   // GPS_RAW_INT
        case 30:  return 39;   // ATTITUDE
        case 33:  return 104;  // GLOBAL_POSITION_INT
        case 74:  return 20;   // VFR_HUD
        default:  return 0;
    }
}

class PacketBuilder {
public:
    std::vector<uint8_t> bytes;
    
    // --- parameters ---
    uint16_t ethertype = 0x0800; // IPv4
    uint8_t  ip_proto  = 17;     // UDP
    uint16_t udp_port  = 14550;  // MAVLink
    
    // MAVLink fields
    uint8_t  sysid     = 1;
    uint32_t msgid     = 0;      // HEARTBEAT
    uint8_t  payload_len = 9;
    
    // error injection
    bool bad_crc = false;
    bool truncate = false;
    size_t truncate_at = 0;
    
    void build() {
        bytes.clear();
        
        // 1. Ethernet Header (14 bytes)
        // dst MAC (broadcast)
        for (int i=0; i<6; i++) bytes.push_back(0xFF);
        // src MAC
        for (int i=0; i<6; i++) bytes.push_back(0x11);
        // ethertype
        bytes.push_back((ethertype >> 8) & 0xFF);
        bytes.push_back(ethertype & 0xFF);
        
        // 2. IP Header (20 bytes)
        bytes.push_back(0x45); // version 4, IHL 5
        bytes.push_back(0x00);
        // total length (20 + 8 + 10 + payload_len + 2)
        uint16_t total_len = 20 + 8 + 10 + payload_len + 2;
        bytes.push_back((total_len >> 8) & 0xFF);
        bytes.push_back(total_len & 0xFF);
        bytes.push_back(0x00); bytes.push_back(0x00); // ID
        bytes.push_back(0x00); bytes.push_back(0x00); // flags
        bytes.push_back(64);   // TTL
        bytes.push_back(ip_proto);
        bytes.push_back(0x00); bytes.push_back(0x00); // checksum (ignored by hardware)
        // src IP (192.168.1.100)
        bytes.push_back(192); bytes.push_back(168); bytes.push_back(1); bytes.push_back(100);
        // dst IP (192.168.1.1)
        bytes.push_back(192); bytes.push_back(168); bytes.push_back(1); bytes.push_back(1);
        
        // 3. UDP Header (8 bytes)
        bytes.push_back(0x00); bytes.push_back(0x00); // src port
        bytes.push_back((udp_port >> 8) & 0xFF);
        bytes.push_back(udp_port & 0xFF);
        uint16_t udp_len = 8 + 10 + payload_len + 2;
        bytes.push_back((udp_len >> 8) & 0xFF);
        bytes.push_back(udp_len & 0xFF);
        bytes.push_back(0x00); bytes.push_back(0x00); // UDP checksum
        
        // 4. MAVLink Header (10 bytes)
        size_t mav_start = bytes.size();
        bytes.push_back(0xFD); // magic
        bytes.push_back(payload_len);
        bytes.push_back(0x00); // incompat
        bytes.push_back(0x00); // compat
        bytes.push_back(0x00); // seq
        bytes.push_back(sysid);
        bytes.push_back(1);    // compid
        bytes.push_back(msgid & 0xFF);
        bytes.push_back((msgid >> 8) & 0xFF);
        bytes.push_back((msgid >> 16) & 0xFF);
        
        // 5. Payload
        for (int i=0; i<payload_len; i++) {
            bytes.push_back(i & 0xFF); // dummy payload
        }
        
        // 6. CRC calculation
        uint16_t crc = 0xFFFF;
        // accumulate over header (excluding 0xFD magic)
        for (size_t i = mav_start + 1; i < bytes.size(); i++) {
            crc = crc_accumulate(bytes[i], crc);
        }
        // accumulate CRC_EXTRA
        crc = crc_accumulate(crc_extra(msgid), crc);
        
        if (bad_crc) crc ^= 0xFFFF; // flip bits
        
        bytes.push_back(crc & 0xFF);
        bytes.push_back((crc >> 8) & 0xFF);
        
        // Truncate if requested (simulates runt frame from MAC)
        if (truncate && truncate_at < bytes.size()) {
            bytes.resize(truncate_at);
        }
    }
};
