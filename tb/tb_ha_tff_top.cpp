/*
 * tb_ha_tff_top.cpp - top-level integration test
 *
 * tests the full ha_tff_top pipeline:
 * AXI-Stream in -> Parser -> Filter -> FIFO -> Wishbone out
 *
 * includes a mock Wishbone master that reads the FIFO and checks
 * the statistics registers. this simulates what the VeeR CPU does.
 *
 * sept 30, 2026
 */

#include <iostream>
#include <memory>
#include <vector>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vha_tff_top.h"
#include "tb_utils.h"

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

class TopTestbench {
public:
    std::unique_ptr<Vha_tff_top> dut;
    std::unique_ptr<VerilatedVcdC> tfp;
    
    TopTestbench(bool trace = false) {
        dut = std::make_unique<Vha_tff_top>();
        if (trace) {
            Verilated::traceEverOn(true);
            tfp = std::make_unique<VerilatedVcdC>();
            dut->trace(tfp.get(), 99);
            tfp->open("ha_tff_top.vcd");
        }
        
        // input inits
        dut->clk = 0;
        dut->rst_n = 0;
        
        // axi
        dut->s_tdata = 0;
        dut->s_tvalid = 0;
        dut->s_tlast = 0;
        
        // wishbone
        dut->wb_adr_i = 0;
        dut->wb_dat_i = 0;
        dut->wb_we_i = 0;
        dut->wb_sel_i = 0;
        dut->wb_stb_i = 0;
        dut->wb_cyc_i = 0;
    }
    
    ~TopTestbench() {
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
    
    // --- Mock Wishbone Master ---
    
    uint32_t wb_read(uint32_t addr) {
        dut->wb_adr_i = addr;
        dut->wb_we_i  = 0;
        dut->wb_sel_i = 0xF;
        dut->wb_stb_i = 1;
        dut->wb_cyc_i = 1;
        
        tick();
        while (!dut->wb_ack_o) {
            tick();
        }
        
        uint32_t data = dut->wb_dat_o;
        
        dut->wb_stb_i = 0;
        dut->wb_cyc_i = 0;
        tick();
        
        return data;
    }
    
    void wb_write(uint32_t addr, uint32_t data) {
        dut->wb_adr_i = addr;
        dut->wb_dat_i = data;
        dut->wb_we_i  = 1;
        dut->wb_sel_i = 0xF;
        dut->wb_stb_i = 1;
        dut->wb_cyc_i = 1;
        
        tick();
        while (!dut->wb_ack_o) {
            tick();
        }
        
        dut->wb_stb_i = 0;
        dut->wb_cyc_i = 0;
        dut->wb_we_i  = 0;
        tick();
    }
    
    // --- Mock AXI Stream MAC ---
    
    void send_frame(const PacketBuilder& pb) {
        for (size_t i = 0; i < pb.bytes.size(); i++) {
            dut->s_tdata = pb.bytes[i];
            dut->s_tvalid = 1;
            dut->s_tlast = (i == pb.bytes.size() - 1);
            
            do {
                tick();
            } while (!dut->s_tready);
        }
        dut->s_tvalid = 0;
        dut->s_tlast = 0;
        
        for(int i=0; i<10; i++) tick(); // drain
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    TopTestbench tb(true);
    
    tb.reset();
    
    // 1. Configure via Wishbone
    std::cout << "[WB] Configuring filter..." << std::endl;
    tb.wb_write(0x20, 1);    // sysid_0 = 1
    tb.wb_write(0x00, 1);    // ctrl = enable
    
    PacketBuilder pb;
    
    // 2. Send valid packet
    std::cout << "[MAC] Sending valid packet (sysid 1)..." << std::endl;
    pb.sysid = 1;
    pb.build();
    tb.send_frame(pb);
    
    // 3. Send invalid packet (sysid 2)
    std::cout << "[MAC] Sending invalid packet (sysid 2)..." << std::endl;
    pb.sysid = 2;
    pb.build();
    tb.send_frame(pb);
    
    // 4. Read stats via Wishbone
    std::cout << "[WB] Reading stats..." << std::endl;
    uint32_t total = tb.wb_read(0x08);
    uint32_t pass  = tb.wb_read(0x0C);
    uint32_t drop  = tb.wb_read(0x10);
    std::cout << "  Total pkts: " << total << std::endl;
    std::cout << "  Passed:     " << pass << std::endl;
    std::cout << "  Dropped:    " << drop << std::endl;
    
    // 5. Read FIFO if IRQ asserted
    if (tb.dut->irq) {
        std::cout << "[WB] IRQ asserted! Reading FIFO..." << std::endl;
        uint32_t status = tb.wb_read(0x04);
        while ((status & 0x1) == 0) { // while not empty
            uint32_t data = tb.wb_read(0x18);
            std::cout << std::hex << "    0x" << data << std::dec << std::endl;
            status = tb.wb_read(0x04);
        }
        std::cout << "[WB] FIFO empty." << std::endl;
    }
    
    std::cout << "Simulation complete." << std::endl;
    return 0;
}
