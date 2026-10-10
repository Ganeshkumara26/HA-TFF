/*
 * tb_mav_filter.cpp - unit test for the mav_filter module
 *
 * tests the MAVLink sysid filtering and hardware CRC calculation.
 * this module receives bytes that have already been stripped of their
 * ethernet/IP/UDP headers by eth_parser.
 *
 * tests:
 *  1. valid packet with correct sysid and CRC
 *  2. wrong sysid (should drop)
 *  3. bad CRC (should drop and pulse stat_crc_err)
 *  4. promiscuous mode (should pass wrong sysid)
 *
 * sept 28, 2026
 */

#include <iostream>
#include <memory>
#include <vector>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vmav_filter.h"
#include "tb_utils.h"

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

class MavFilterTestbench {
public:
    std::unique_ptr<Vmav_filter> dut;
    std::unique_ptr<VerilatedVcdC> tfp;
    
    MavFilterTestbench(bool trace = false) {
        dut = std::make_unique<Vmav_filter>();
        if (trace) {
            Verilated::traceEverOn(true);
            tfp = std::make_unique<VerilatedVcdC>();
            dut->trace(tfp.get(), 99);
            tfp->open("mav_filter.vcd");
        }
        
        dut->clk = 0;
        dut->rst_n = 0;
        dut->mav_data = 0;
        dut->mav_valid = 0;
        dut->mav_last = 0;
        dut->mav_sof = 0;
        
        // setup allow-list (sysid 1 is allowed)
        dut->allowed_sysid[0] = 1;
        dut->sysid_valid = 1; // bit 0 high
        dut->promisc_mode = 0;
    }
    
    ~MavFilterTestbench() {
        if (tfp) tfp->close();
    }
    
    void tick() {
        dut->clk = 0;
        dut->eval();
        if (tfp) tfp->dump(main_time);
        main_time += 5;
        
        dut->clk = 1;
        dut->eval();
        if (tfp) tfp->dump(main_time);
        main_time += 5;
    }
    
    void reset() {
        dut->rst_n = 0;
        tick(); tick();
        dut->rst_n = 1;
        tick();
    }
    
    void send_mavlink(const PacketBuilder& pb) {
        // extract just the MAVLink part (skip eth/ip/udp)
        // MAVLink starts at byte 42 for a standard packet
        size_t start_idx = 14 + 20 + 8;
        
        for (size_t i = start_idx; i < pb.bytes.size(); i++) {
            dut->mav_data = pb.bytes[i];
            dut->mav_valid = 1;
            dut->mav_last = (i == pb.bytes.size() - 1);
            dut->mav_sof = (i == start_idx); // 0xFD is the first byte
            
            tick();
        }
        
        dut->mav_valid = 0;
        dut->mav_last = 0;
        dut->mav_sof = 0;
        
        for(int i=0; i<10; i++) tick();
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    MavFilterTestbench tb(true);
    
    tb.reset();
    PacketBuilder pb;
    
    std::cout << "--- TEST 1: Valid Sysid (1) and CRC ---" << std::endl;
    pb.sysid = 1;
    pb.build();
    tb.send_mavlink(pb);
    
    std::cout << "--- TEST 2: Wrong Sysid (2) ---" << std::endl;
    pb.sysid = 2;
    pb.build();
    tb.send_mavlink(pb);
    
    std::cout << "--- TEST 3: Bad CRC ---" << std::endl;
    pb.sysid = 1;
    pb.bad_crc = true;
    pb.build();
    tb.send_mavlink(pb);
    pb.bad_crc = false;
    
    std::cout << "--- TEST 4: Promiscuous Mode (Wrong Sysid) ---" << std::endl;
    pb.sysid = 5; // not in list
    pb.build();
    tb.dut->promisc_mode = 1;
    tb.send_mavlink(pb);
    
    std::cout << "Tests complete. Check mav_filter.vcd for results." << std::endl;
    return 0;
}
