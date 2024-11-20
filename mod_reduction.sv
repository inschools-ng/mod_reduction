`timescale 1ps/1ps

module ModReduction #(
    parameter int USE_MULT = 1,   // if 1, use the multiplier - uses dsp, less blocks
    parameter int BIT_LEN = 256
)(
    input  logic                  clk,
    input  logic                  reset,
    input  logic [299:0]          X,        // take in 300-bit input
    output logic [255:0]          O,        // 256-bit result (X mod P) designed using the montgomery reduction
    output logic                  busy
);

    parameter logic [255:0] P = 256'h104899928942039473597645237135751317405745389583683433800060134911610808289117; // constant prime of p

    typedef enum logic [2:0] {
        INIT       = 3'd0,
        TRANSFORM  = 3'd1,
        MULTIPLY   = 3'd2,
        REDUCE     = 3'd3,
        FINALIZE   = 3'd4,
        FINISH     = 3'd5
    } state_t;

    state_t state;

    logic [299:0] input_reg;          // internal egister to hold input X
    logic [255:0] T, M, Q;            // defined internal registers (temporary
    logic [511:0] product, mult_out;  // defined product for intermediate calculations
    logic [255:0] csa_terms[2:0];     // defined registerto the carry-save adder tree
    logic [255:0] csa_result[1:0];    // defined register from the carry-save adder tree


    always_ff @(posedge clk or posedge reset) begin 
        if (reset) begin
            busy <= 1'b0;   // track the busy signal here 
        end else if (state == INIT || state == FINISH) begin
            busy <= 1'b0;
        end else begin
            busy <= 1'b1;
        end
    end

    generate
        if (USE_MULT) begin : GEN_MULTIPLIER    
            multiplier #(           // multiplier uses DSP for instantiation of efficient multiplication
                .A_BIT_LEN(256),
                .B_BIT_LEN(256),
                .MUL_OUT_BIT_LEN(512)
            ) mont_multiplier (
                .clk(clk),
                .A(M),
                .B(Q),
                .P(mult_out)
            );
        end else begin : GEN_SHIFT_ADD
            always_comb begin   // shift-and-add-based multiplication for the Zybo 7000 board
                mult_out = (M << 32) + (M << 9) + (M << 8) + (M << 7) + (M << 6) + (M << 4) + M + Q;
            end
        end
    endgenerate

    carry_save_adder_tree_level #(  // instantiate the carry adder, modular addition 
        .NUM_ELEMENTS(3),
        .BIT_LEN(256)
    ) csa_tree (
        .terms(csa_terms),
        .results(csa_result)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= INIT;
            O <= 256'b0;
        end else begin
            case (state)
                INIT: begin
                    input_reg <= X;
                    state <= TRANSFORM;
                end

                TRANSFORM: begin
                    // montgomery form, T = X * R mod P, R = 2^256
                    T <= input_reg[255:0] << BIT_LEN; // T = X * R mod P
                    M <= T % P;                       // reduce mod P
                    state <= MULTIPLY;
                end
                MULTIPLY: begin
                    // modular multiplication
                    Q <= mult_out[255:0];             // lower 256 bits as Q
                    T <= mult_out[511:256] % P;       // upper 256 bits mod P in T
                    state <= REDUCE;
                end
                REDUCE: begin
                    // modular reduction (carry-save adder)
                    csa_terms[0] = T;
                    csa_terms[1] = Q;
                    csa_terms[2] = P;
                    M <= csa_result[0];               // M takes the result of the carry save adder
                    state <= FINALIZE;
                end
                FINALIZE: begin
                    // is the result within P? [0, P-1]
                    if (M >= P) begin
                        O <= M - P;                   // here if M >= P, subtract P
                    end else begin
                        O <= M;
                    end
                    state <= FINISH;
                end

                FINISH: begin
                    state <= INIT;                
                end

                default: state <= INIT;               
            endcase
        end
    end
endmodule

module multiplier #(
    parameter integer A_BIT_LEN = 256,
    parameter integer B_BIT_LEN = 256,
    parameter integer MUL_OUT_BIT_LEN = 512
)(
    input  logic clk,
    input  logic [A_BIT_LEN-1:0] A,
    input  logic [B_BIT_LEN-1:0] B,
    output logic [MUL_OUT_BIT_LEN-1:0] P
);
    always_ff @(posedge clk) begin
        P <= A * B;
    end
endmodule

module carry_save_adder_tree_level #(
    parameter int NUM_ELEMENTS = 3,
    parameter int BIT_LEN = 256
)(
    input  logic [BIT_LEN-1:0] terms[NUM_ELEMENTS],
    output logic [BIT_LEN-1:0] results[1:0]
);
    genvar i;
    generate
        for (i = 0; i < (NUM_ELEMENTS / 3); i++) begin : csa_insts
            carry_save_adder #(.BIT_LEN(BIT_LEN)) carry_save_adder_inst (
                .A(terms[i*3]),
                .B(terms[(i*3)+1]),
                .Cin(terms[(i*3)+2]),
                .Cout(results[i]),
                .S(results[i+1])
            );
        end
    endgenerate
endmodule

module carry_save_adder #(
    parameter int BIT_LEN = 256
)(
    input  logic [BIT_LEN-1:0] A,
    input  logic [BIT_LEN-1:0] B,
    input  logic [BIT_LEN-1:0] Cin,
    output logic [BIT_LEN-1:0] Cout,
    output logic [BIT_LEN-1:0] S
);
    genvar i;
    generate
        for (i = 0; i < BIT_LEN; i++) begin : csa_fas
            full_adder full_adder_inst(
                .A(A[i]),
                .B(B[i]),
                .Cin(Cin[i]),
                .Cout(Cout[i]),
                .S(S[i])
            );
        end
    endgenerate
endmodule

module full_adder (
    input  logic A,
    input  logic B,
    input  logic Cin,
    output logic Cout,
    output logic S
);
    assign S = A ^ B ^ Cin;
    assign Cout = (A & B) | (Cin & (A ^ B));
endmodule
