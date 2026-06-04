`timescale 1ns/1ps
// Module: scloudplus_matmul_serial
// Purpose: serial block scheduler using one Scloud+ BMM block.

module scloudplus_matmul_serial #(
    parameter B = 8,
    parameter Q_WIDTH = 12,
    parameter ACC_WIDTH = 16,
    parameter IDX_WIDTH = 16,
    parameter CFG_WIDTH = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [CFG_WIDTH-1:0]         cfg_b_active,
    input  wire [CFG_WIDTH-1:0]         cfg_q_active,
    input  wire [1:0]                   cfg_coeff_mode,
    input  wire [IDX_WIDTH-1:0]         cfg_row_blocks,
    input  wire [IDX_WIDTH-1:0]         cfg_inner_blocks,
    input  wire [IDX_WIDTH-1:0]         cfg_col_blocks,
    output wire                         start_ready,
    output reg                          busy,
    output reg                          done,
    output reg                          blk_req_valid,
    input  wire                         blk_req_ready,
    output reg  [IDX_WIDTH-1:0]         a_row_blk,
    output reg  [IDX_WIDTH-1:0]         a_col_blk,
    output reg  [IDX_WIDTH-1:0]         s_col_blk,
    input  wire                         blk_in_valid,
    input  wire [B*B*Q_WIDTH-1:0]       a_block,
    input  wire [B*B*2-1:0]             s_block,
    output reg                          c_block_valid,
    input  wire                         c_block_ready,
    output reg  [IDX_WIDTH-1:0]         c_row_blk,
    output reg  [IDX_WIDTH-1:0]         c_col_blk,
    output reg  [B*B*Q_WIDTH-1:0]       c_block
);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_REQ  = 3'd1;
    localparam [2:0] ST_WAIT = 3'd2;
    localparam [2:0] ST_ACC  = 3'd3;
    localparam [2:0] ST_EMIT = 3'd4;
    localparam [2:0] ST_DONE = 3'd5;

    reg [2:0] state;
    reg [B*B*Q_WIDTH-1:0] acc_block;

    wire [B*B*Q_WIDTH-1:0] product_block;
    wire [B*B*Q_WIDTH-1:0] next_acc_block;
    wire [IDX_WIDTH-1:0] cfg_row_blocks_eff;
    wire [IDX_WIDTH-1:0] cfg_inner_blocks_eff;
    wire [IDX_WIDTH-1:0] cfg_col_blocks_eff;
    wire [IDX_WIDTH-1:0] cfg_row_last;
    wire [IDX_WIDTH-1:0] cfg_inner_last;
    wire [IDX_WIDTH-1:0] cfg_col_last;
    wire last_inner;
    wire last_col;
    wire last_row;

    assign start_ready = (state == ST_IDLE);
    assign cfg_row_blocks_eff   = (cfg_row_blocks == {IDX_WIDTH{1'b0}}) ? {{(IDX_WIDTH-1){1'b0}}, 1'b1} : cfg_row_blocks;
    assign cfg_inner_blocks_eff = (cfg_inner_blocks == {IDX_WIDTH{1'b0}}) ? {{(IDX_WIDTH-1){1'b0}}, 1'b1} : cfg_inner_blocks;
    assign cfg_col_blocks_eff   = (cfg_col_blocks == {IDX_WIDTH{1'b0}}) ? {{(IDX_WIDTH-1){1'b0}}, 1'b1} : cfg_col_blocks;
    assign cfg_row_last         = cfg_row_blocks_eff - {{(IDX_WIDTH-1){1'b0}}, 1'b1};
    assign cfg_inner_last       = cfg_inner_blocks_eff - {{(IDX_WIDTH-1){1'b0}}, 1'b1};
    assign cfg_col_last         = cfg_col_blocks_eff - {{(IDX_WIDTH-1){1'b0}}, 1'b1};
    assign last_inner     = (a_col_blk == cfg_inner_last);
    assign last_col       = (s_col_blk == cfg_col_last);
    assign last_row       = (a_row_blk == cfg_row_last);

    scloudplus_bmm_block #(
        .B(B),
        .Q_WIDTH(Q_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .CFG_WIDTH(CFG_WIDTH)
    ) u_bmm_block (
        .cfg_b_active(cfg_b_active),
        .cfg_q_active(cfg_q_active),
        .cfg_coeff_mode(cfg_coeff_mode),
        .a_block(a_block),
        .s_block(s_block),
        .c_block(product_block)
    );

    scloudplus_block_add #(
        .B(B),
        .Q_WIDTH(Q_WIDTH),
        .CFG_WIDTH(CFG_WIDTH)
    ) u_acc_add (
        .cfg_q_active(cfg_q_active),
        .a_block(acc_block),
        .b_block(product_block),
        .y_block(next_acc_block)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            blk_req_valid   <= 1'b0;
            a_row_blk       <= {IDX_WIDTH{1'b0}};
            a_col_blk       <= {IDX_WIDTH{1'b0}};
            s_col_blk       <= {IDX_WIDTH{1'b0}};
            c_block_valid   <= 1'b0;
            c_row_blk       <= {IDX_WIDTH{1'b0}};
            c_col_blk       <= {IDX_WIDTH{1'b0}};
            c_block         <= {B*B*Q_WIDTH{1'b0}};
            acc_block       <= {B*B*Q_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy          <= 1'b0;
                    blk_req_valid <= 1'b0;
                    c_block_valid <= 1'b0;
                    if (start) begin
                        busy      <= 1'b1;
                        a_row_blk <= {IDX_WIDTH{1'b0}};
                        a_col_blk <= {IDX_WIDTH{1'b0}};
                        s_col_blk <= {IDX_WIDTH{1'b0}};
                        acc_block <= {B*B*Q_WIDTH{1'b0}};
                        state     <= ST_REQ;
                    end
                end
                ST_REQ: begin
                    blk_req_valid <= 1'b1;
                    if (blk_req_valid && blk_req_ready) begin
                        blk_req_valid <= 1'b0;
                        state         <= ST_WAIT;
                    end
                end
                ST_WAIT: begin
                    if (blk_in_valid) begin
                        state <= ST_ACC;
                    end
                end
                ST_ACC: begin
                    acc_block <= next_acc_block;
                    if (last_inner) begin
                        c_block       <= next_acc_block;
                        c_row_blk     <= a_row_blk;
                        c_col_blk     <= s_col_blk;
                        c_block_valid <= 1'b1;
                        state         <= ST_EMIT;
                    end else begin
                        a_col_blk <= a_col_blk + {{(IDX_WIDTH-1){1'b0}}, 1'b1};
                        state     <= ST_REQ;
                    end
                end
                ST_EMIT: begin
                    if (c_block_ready) begin
                        c_block_valid <= 1'b0;
                        acc_block     <= {B*B*Q_WIDTH{1'b0}};
                        a_col_blk     <= {IDX_WIDTH{1'b0}};
                        if (last_col && last_row) begin
                            state <= ST_DONE;
                        end else if (last_col) begin
                            s_col_blk <= {IDX_WIDTH{1'b0}};
                            a_row_blk <= a_row_blk + {{(IDX_WIDTH-1){1'b0}}, 1'b1};
                            state     <= ST_REQ;
                        end else begin
                            s_col_blk <= s_col_blk + {{(IDX_WIDTH-1){1'b0}}, 1'b1};
                            state     <= ST_REQ;
                        end
                    end
                end
                ST_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
