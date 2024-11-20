`timescale 1ps/1ps

module ModReduction_tb;

  localparam CLK_PERIOD = 100;

  logic clk, reset;
  logic start;
  logic [299:0] X;
  logic busy;
  logic [255:0] O;
  logic [255:0] expected;

  ModReduction modReduction (
      .clk(clk),
      .reset(reset),
      .X(X),
      .O(O),
      .busy(busy)
  );

  initial begin
      clk = 0;
      forever #CLK_PERIOD clk = ~clk;
  end

  initial begin
      reset = 0;
      repeat(2) #(20 * CLK_PERIOD) reset = ~reset;
  end

  always_ff @(posedge clk) begin
      if (busy && (O === 'bx || O === 'bz)) begin
          $error("%m %t ERROR: Output O is invalid (X or Z state)", $time);
      end
  end

  // single 300 bit int 
  task test_single(input [299:0] test_input, input [255:0] expected_output);
  begin
      start = 0;
      X = test_input;
      expected = expected_output;
      @(posedge clk); #10;
      start = 1;
      @(posedge clk); #10;
      start = 0;

      wait(!busy);
      #10;  // ensure stable output - wait for 10 ns

      if (O === expected) begin
          $display("PASS: X = %h, O = %h", X, O);
      end else begin
          $display("FAIL: X = %h, Expected = %h, Got = %h", X, expected, O);
      end
  end
  endtask

  //any random 300-bit int
  task test_randomized();
  begin
      integer i;
      logic [299:0] random_X;
      logic [255:0] modulus = 256'h104899928942039473597645237135751317405745389583683433800060134911610808289117;

      for (i = 0; i < 100; i++) begin
          random_X = $random;
          random_X = random_X % (modulus * modulus);  // constraint random input within a range larger than modulus
          expected = random_X % modulus;             

          test_single(random_X, expected); // what do we get if we run the single test for any random input integer?
      end
  end
  endtask

  // boundary and edge cases 
  task test_boundaries();
  begin
      logic [299:0] boundary_X [2];
      boundary_X[0] = 300'd0; // 300 bit int -Lower boundary
      boundary_X[1] = 300'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // similarly, upper boundary of 300 buts. maxi

      // boundary gives the same result as the unit test.
      logic [255:0] expected_boundary [2];
      expected_boundary[0] = 256'd0;                
      expected_boundary[1] = boundary_X[1] % 256'h104899928942039473597645237135751317405745389583683433800060134911610808289117; // expected result for upper boundary

      for (int i = 0; i < 2; i++) begin
          test_single(boundary_X[i], expected_boundary[i]);
      end
  end
  endtask

  // check for busy signal and latnecy. 
  task test_latency();
  begin
      logic [299:0] test_input;
      logic [255:0] modulus = 256'h104899928942039473597645237135751317405745389583683433800060134911610808289117;
      integer start_time, end_time, latency;

      test_input = 300'h123456789ABCDEF;
      expected = test_input % modulus;

      start = 0;
      X = test_input;
      @(posedge clk); #10;
      start = 1;
      @(posedge clk); #10;
      start = 0;
      start_time = $time;

      wait(!busy);

      end_time = $time;
      latency = end_time - start_time;
      $display("INFO: Latency for ModReduction operation: %0d ps", latency);

      if (O === expected) begin
          $display("PASS: Latency Test - X = %h, O = %h, Latency = %0d", X, O, latency);
      end else begin
          $display("FAIL: Latency Test - X = %h, Expected = %h, Got = %h", X, expected, O);
      end
  end
  endtask

  initial begin
      @(negedge reset);
      
      $display("Running specific test...");
      test_single(300'h1 << 43, 256'h822752465816620949324161418291805943222876982255305228346720256);
      
      $display("Running boundary tests...");
      test_boundaries();

      $display("Running randomized tests...");
      test_randomized();

      $display("Running latency test...");
      test_latency();

      #1us $finish;
  end

endmodule
