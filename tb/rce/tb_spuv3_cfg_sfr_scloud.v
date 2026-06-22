`timescale 1ns/1ps

module tb_spuv3_cfg_sfr_scloud;

    localparam BASE = 32'h0000_4000;

    reg clk;
    reg rst_n;
    reg [31:0] sfr_addr;
    reg sfr_write;
    reg [31:0] sfr_wdata;
    reg sfr_sel;
    wire [31:0] sfr_rdata;
    reg [31:0] spuv3_wr_mstatus;
    reg spuv3_cfg_clr;
    wire [31:0] spuv3_cfg;
    wire [31:0] spuv3_cfg_int;
    wire [31:0] scloud_msg_in_base;
    wire [31:0] scloud_msg_out_base;
    wire [31:0] scloud_q_in_base;
    wire [31:0] scloud_q_aux_base;
    wire [31:0] scloud_q_out_base;

    integer error_count;

    spuv3_cfg_sfr_scloud #(
        .SFR_CFG_BASE_ADDR(BASE)
    ) dut (
        .sys_clk             (clk),
        .sys_rst_n           (rst_n),
        .sfr_addr            (sfr_addr),
        .sfr_write           (sfr_write),
        .sfr_wdata           (sfr_wdata),
        .sfr_sel             (sfr_sel),
        .sfr_rdata           (sfr_rdata),
        .spuv3_wr_mstatus    (spuv3_wr_mstatus),
        .spuv3_cfg_clr       (spuv3_cfg_clr),
        .spuv3_cfg           (spuv3_cfg),
        .spuv3_cfg_int       (spuv3_cfg_int),
        .scloud_msg_in_base  (scloud_msg_in_base),
        .scloud_msg_out_base (scloud_msg_out_base),
        .scloud_q_in_base    (scloud_q_in_base),
        .scloud_q_aux_base   (scloud_q_aux_base),
        .scloud_q_out_base   (scloud_q_out_base)
    );

    always #5 clk = ~clk;

    task sfr_write_word;
        input [31:0] byte_addr;
        input [31:0] data;
        begin
            @(negedge clk);
            sfr_addr  = byte_addr >> 2;
            sfr_wdata = data;
            sfr_sel   = 1'b1;
            sfr_write = 1'b1;
            @(negedge clk);
            sfr_sel   = 1'b0;
            sfr_write = 1'b0;
        end
    endtask

    task check_word;
        input [255:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got !== expected) begin
                error_count = error_count + 1;
                $display("FAIL %0s got=%h expected=%h", name, got, expected);
            end else begin
                $display("OK %0s value=%h", name, got);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sfr_addr = 32'b0;
        sfr_write = 1'b0;
        sfr_wdata = 32'b0;
        sfr_sel = 1'b0;
        spuv3_wr_mstatus = 32'b0;
        spuv3_cfg_clr = 1'b0;
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        check_word("msg_in_reset",  scloud_msg_in_base,  32'h0000_0000);
        check_word("msg_out_reset", scloud_msg_out_base, 32'h0000_0004);
        check_word("q_in_reset",    scloud_q_in_base,    32'h0000_0008);
        check_word("q_aux_reset",   scloud_q_aux_base,   32'h0000_0010);
        check_word("q_out_reset",   scloud_q_out_base,   32'h0000_0018);

        sfr_write_word(BASE + 32'h08, 32'h0000_0020);
        sfr_write_word(BASE + 32'h0c, 32'h0000_0024);
        sfr_write_word(BASE + 32'h10, 32'h0000_0030);
        sfr_write_word(BASE + 32'h14, 32'h0000_0040);
        sfr_write_word(BASE + 32'h18, 32'h0000_0050);

        check_word("msg_in_write",  scloud_msg_in_base,  32'h0000_0020);
        check_word("msg_out_write", scloud_msg_out_base, 32'h0000_0024);
        check_word("q_in_write",    scloud_q_in_base,    32'h0000_0030);
        check_word("q_aux_write",   scloud_q_aux_base,   32'h0000_0040);
        check_word("q_out_write",   scloud_q_out_base,   32'h0000_0050);

        sfr_write_word(BASE + 32'h04, 32'h0000_0001);
        sfr_write_word(BASE + 32'h00, 32'h4000_1383);
        check_word("cfg_write", spuv3_cfg, 32'h4000_1383);

        @(negedge clk);
        spuv3_wr_mstatus = 32'h0012_3456;
        spuv3_cfg_clr = 1'b1;
        @(negedge clk);
        spuv3_cfg_clr = 1'b0;

        if (spuv3_cfg[31] !== 1'b1 || spuv3_cfg[30] !== 1'b0) begin
            error_count = error_count + 1;
            $display("FAIL cfg done/start semantics cfg=%h", spuv3_cfg);
        end
        check_word("int_set", spuv3_cfg_int, 32'h0000_0003);

        sfr_write_word(BASE + 32'h04, 32'h0000_0003);
        check_word("int_w1c", spuv3_cfg_int, 32'h0000_0001);

        if (error_count == 0)
            $display("TB_PASS spuv3_cfg_sfr_scloud");
        else
            $display("TB_FAIL spuv3_cfg_sfr_scloud errors=%0d", error_count);

        $finish;
    end

endmodule
