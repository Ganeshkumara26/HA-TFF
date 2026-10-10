/*
 * tb_eth_parser.cpp - unit test for the eth_parser module
 *
 * this uses Verilator to simulate the SystemVerilog eth_parser.sv.
 * i wrote this because debugging FSMs in vivado's simulator is too slow.
 * verilator compiles the SV to C++ and runs it natively. it's insanely fast.
 * 
 * tests:
 *  1. valid packet (checks that 5-tuple is extracted correctly)
 *  2. non-IPv4 packet (ARP) - should be dropped
 *  3. non-UDP packet (TCP) - should be dropped
 *  4. wrong UDP port - should be dropped
 *  5. runt packet (truncated before header complete) - should drop cleanly
 *
 * sept 26, 2026
 */

#include <iostream>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Veth_parser.h"
#include "tb_utils.h"

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

class EthParserTestbench {
public:
    std::unique_ptr<Veth_parser> dut;
    std::unique_ptr<VerilatedVcdC> tfp;
    
    EthParserTestbench(bool trace = false) {
        dut = std::make_unique<Veth_parser>();
        if (trace) {
            Verilated::traceEverOn(true);
            tfp = std::make_unique<VerilatedVcdC>();
            dut->trace(tfp.get(), 99);
            tfp->open("eth_parser.vcd");
        }
        
        // initialize inputs
        dut->clk = 0;
        dut->rst_n = 0;
        dut->s_tdata = 0;
        dut->s_tvalid = 0;
        dut->s_tlast = 0;
        dut->enable = 1;
        dut->drop_non_ip = 1;
    }
    
    ~EthParserTestbench() {
        if (tfp) {
            tfp->close();
        }
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
    
    void send_packet(const PacketBuilder& builder) {
        for (size_t i = 0; i < builder.bytes.size(); i++) {
            dut->s_tdata = builder.bytes[i];
            dut->s_tvalid = 1;
            dut->s_tlast = (i == builder.bytes.size() - 1);
            
            do {
                tick();
            } while (!dut->s_tready);
        }
        
        dut->s_tvalid = 0;
        dut->s_tlast = 0;
        
        // flush
        for(int i=0; i<10; i++) tick();
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    EthParserTestbench tb(true);
    
    tb.reset();
    
    PacketBuilder pb;
    
    std::cout << "--- TEST 1: Valid Packet ---" << std::endl;
    pb.build();
    tb.send_packet(pb);
    // check stats manually via trace for now. 
    // real constrained-random TB would have a scoreboard here.
    
    std::cout << "--- TEST 2: ARP Packet ---" << std::endl;
    pb.ethertype = 0x0806;
    pb.build();
    tb.send_packet(pb);
    pb.ethertype = 0x0800; // restore
    
    std::cout << "--- TEST 3: TCP Packet ---" << std::endl;
    pb.ip_proto = 6;
    pb.build();
    tb.send_packet(pb);
    pb.ip_proto = 17; // restore
    
    std::cout << "--- TEST 4: Wrong UDP Port ---" << std::endl;
    pb.udp_port = 80;
    pb.build();
    tb.send_packet(pb);
    pb.udp_port = 14550; // restore
    
    std::cout << "--- TEST 5: Runt Packet (Truncated in IP header) ---" << std::endl;
    pb.truncate = true;
    pb.truncate_at = 18; // cuts off before IP header is done
    pb.build();
    tb.send_packet(pb);
    
    std::cout << "Tests complete. Check eth_parser.vcd for results." << std::endl;
    return 0;
}
