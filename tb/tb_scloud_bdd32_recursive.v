`timescale 1ns/1ps

module tb_scloud_bdd32_recursive;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;
    localparam DELTA   = 10'd256;

    reg  [(COORDS*Q_WIDTH)-1:0] target_flat;
    reg  [(COORDS*Q_WIDTH)-1:0] expected_flat;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_flat;

    integer idx;
    integer error_count;

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (TAU),
        .COMPLEX_N(16)
    ) dut (
        .target_flat (target_flat),
        .decoded_flat(decoded_flat)
    );

    task set_coord;
        input integer coord_idx;
        input [Q_WIDTH-1:0] value;
        begin
            target_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = value;
        end
    endtask

    task set_expected_coord;
        input integer coord_idx;
        input [Q_WIDTH-1:0] value;
        begin
            expected_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = value;
        end
    endtask

    task add_noise_coord;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            target_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] =
                target_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] + noise_tc;
        end
    endtask

    task check_case;
        input [127:0] name;
        begin
            #1;
            if (decoded_flat !== expected_flat) begin
                error_count = error_count + 1;
                $display("FAIL %0s decoded=%h expected=%h target=%h",
                         name, decoded_flat, expected_flat, target_flat);
            end else begin
                $display("PASS %0s", name);
            end
        end
    endtask

    task check_flat_case;
        input [127:0] name;
        input [(COORDS*Q_WIDTH)-1:0] expected_value;
        input [(COORDS*Q_WIDTH)-1:0] target_value;
        begin
            expected_flat = expected_value;
            target_flat = target_value;
            check_case(name);
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_bdd32_recursive.vcd");
        $dumpvars(0, tb_scloud_bdd32_recursive);

        error_count = 0;
        target_flat = {COORDS*Q_WIDTH{1'b0}};
        expected_flat = {COORDS*Q_WIDTH{1'b0}};
        #5;

        target_flat = {COORDS*Q_WIDTH{1'b0}};
        expected_flat = {COORDS*Q_WIDTH{1'b0}};
        add_noise_coord(0,  10'd17);
        add_noise_coord(1,  10'h3f1);
        add_noise_coord(5,  10'd63);
        add_noise_coord(9,  10'h3e2);
        add_noise_coord(17, 10'd75);
        add_noise_coord(31, 10'h3d0);
        check_case("zero_noise");

        target_flat = {COORDS*Q_WIDTH{1'b0}};
        expected_flat = {COORDS*Q_WIDTH{1'b0}};
        for (idx = 0; idx < 16; idx = idx + 1) begin
            set_coord(2*idx, DELTA);
            set_coord((2*idx)+1, 10'd0);
            set_expected_coord(2*idx, DELTA);
            set_expected_coord((2*idx)+1, 10'd0);
        end
        add_noise_coord(0,  10'd17);
        add_noise_coord(2,  10'h3f8);
        add_noise_coord(7,  10'd31);
        add_noise_coord(12, 10'h3e8);
        add_noise_coord(20, 10'd64);
        add_noise_coord(27, 10'h3f0);
        check_case("all_real_delta_noise");

        check_flat_case("rec00", 320'h4010000000802004010000000401004010080200c010000000002004010080200c0100c030000200, 320'h3c50ff94197f60337d1ff8c1b3cd0b34d2b7e605bad13f6c23001f745cef8a5fbc1ce1c76f503600);
        check_flat_case("rec01", 320'h4010000200000004030000200c0100c01000020000000c01004010080000c01008000080000c0100, 320'h4b4ff00dd10c7df48ee9065efc34d5ca4e1085f5027edc552e344fb81ff1c44e58742576400c00d5);
        check_flat_case("rec02", 320'h40300403008000080000401004030080000000000000000000c0100403008020000200c030040300, 320'h4cacc3bb147f804770263812239b1c7d00ef582c073e2fe808b612a37b24841ee00200bab1834b30);
        check_flat_case("rec03", 320'h803000030040200c02008030080100c000040000c0200c02008010080100c0000c00008030000100, 320'h7d70d002f143de5c65fd80edf87ce3c6ff342fd3cadf9c15eb84cdb88d00bdc17bbc297ef07f851d);
        check_flat_case("rec04", 320'h80200002000020080200800008020000000800008020000200802008000000000800000000080000, 320'h80200f562dffe037463177c237a619fbc0d7542978621fd6097b6158bbd1fec077c411f941d897d9);
        check_flat_case("rec05", 320'h40100000004010080200000004010000000c03004030000000c01008020000000c010000000c0100, 320'h460d20c032330ee851fe013dc498e008be6c72f443ad60b01cb88fa821d80abdec9110fb800c00ea);
        check_flat_case("rec06", 320'h003000010040000400008010080100c0200c0000001008010040000c020080300803004000040200, 320'h01ee1074f5434003c40f795197f503b7e1fb8c1bfcd0b74d2b3e405bae1376f23802f745fef4a5fb);
        check_flat_case("rec07", 320'h4010080000c030000000800004030000200c03004030000200c03008000000000c01008000040300, 320'h4752576400c02d50b7ff80fd14c6df08de9c66ef436d50a5e1c86f5827ed0542eb44fb81ff1446e5);
        check_flat_case("rec08", 320'h80200c0100c030000200403008000080000c01008020040300c030080000403008000080000c0100, 320'h80200ba918b4b300c9cc3bb147f80477026b812279a1c3d30eb5b2c873e23eb087602a77824c40ee);
        check_flat_case("rec09", 320'h00000401004030080000800004030040100000000000040100401008020080000c0100c010000200, 320'hfbc293ed073871d7d40d803f143ee5464fd00fdf07fe346cf342cd38adf9817ebc4cdbc8d00fde17);
        check_flat_case("rec10", 320'h8030000100c0000400000010000100c0000c0200803008010040200402008010000100c020040000, 320'h7c711f951dc97d940000f552dffd03b4431b7e237a7197bd0d35629386217d509fb515cb9d13ec07);
        check_flat_case("rec11", 320'h802004010080000c0300c010000000c0100002008020040300002004030040100000004010000200, 320'h892103b900803eac62d2cc132f33eec50fe011dc899e048ae6071f443ad64b11cf8bfa420d80a9de);

        if (error_count == 0) begin
            $display("TB_PASS scloud_bdd32_recursive");
        end else begin
            $display("TB_FAIL scloud_bdd32_recursive errors=%0d", error_count);
        end
        $finish;
    end

endmodule
