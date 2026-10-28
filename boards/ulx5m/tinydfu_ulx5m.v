/*
 *  TinyDFU Bootloader for the  Intergalaktik ULX5M FPGA board.
 *  (based on the Logicbone ECP5 bootloader)
 */

module tinydfu_ulx5m (
    input        refclk,
    output       resetn,

    inout        usb_ufp_dp,
    inout        usb_ufp_dm,
    output       usb_ufp_pull,

    output       [3:0] led,
    output r,

    output       flash_csel,
    output       flash_sclk,
    output       flash_mosi,
    input        flash_miso
);

wire clk270, clk180, clk90, clk_48mhz, usr_ref_out;
wire usr_pll_lock_stdy, usr_pll_lock;

CC_PLL #(
    .REF_CLK("25.0"),    // reference input in MHz
    .OUT_CLK("48.0"),    // pll output frequency in MHz
    .LOW_JITTER(1),      // 0: disable, 1: enable low jitter mode
    .CI_FILTER_CONST(2), // optional CI filter constant
    .CP_FILTER_CONST(4)  // optional CP filter constant
) pll_inst (
    .CLK_REF(refclk), .CLK_FEEDBACK(1'b0), .USR_CLK_REF(1'b0),
    .USR_LOCKED_STDY_RST(1'b0), .USR_PLL_LOCKED_STDY(usr_pll_lock_stdy), .USR_PLL_LOCKED(usr_pll_lock),
    .CLK270(clk270), .CLK180(clk180), .CLK90(clk90), .CLK0(clk_48mhz), .CLK_REF_OUT(usr_ref_out)
);

reg  clk_24mhz = 0;
reg  clk = 0;
always @(posedge clk_48mhz) clk_24mhz <= ~clk_24mhz;
always @(posedge clk_24mhz) clk <= ~clk;

//////////////////////////
// LED Patterns
//////////////////////////
reg [31:0] led_counter;
always @(posedge clk) begin
    led_counter <= led_counter + 1;
end

// Simple blink pattern when idle.
wire [3:0] led_idle = {3'b0, led_counter[21]};

// Cylon pattern when programming.
reg [2:0] led_cylon_count = 0;
reg [3:0] led_cylon = 4'b0;
always @(posedge led_counter[20]) begin
   if (led_cylon_count) led_cylon_count <= led_cylon_count - 1;
   else led_cylon_count <= 5;

   if (led_cylon_count == 4) led_cylon <= 4'b0100;
   else if (led_cylon_count == 5) led_cylon <= 4'b0010;
   else led_cylon <= 4'b0001 << led_cylon_count[1:0];
end

// Select the LED pattern by DFU state.
wire [7:0] dfu_state;
assign led = (dfu_state == 'h02) ? ~led_idle : ~led_cylon;

//////////////////////////
// Reset and Multiboot
//////////////////////////

reg user_boot_now = 1'b0;
reg user_auto_boot = 1'b1;

reg [15:0] reset_delay = 16'hff_ff;
reg [31:0] boot_delay = (12000000 * 5);
wire dfu_detach;
always @(posedge clk) begin

	if (reset_delay) reset_delay <= reset_delay - 1;
   if (boot_delay) boot_delay <= boot_delay - 1;

   // if the user does something with dfu, cancel auto boot
   if (dfu_state > 2) user_auto_boot = 1'b0;

   // if the user detaches, boot now
   if (dfu_detach) user_boot_now = 1'b1;

   // if autoboot is enabled and the timer ends, boot now
   if (user_auto_boot && boot_delay == 0) user_boot_now = 1'b1;

end

assign r =  reset_delay != 0;
assign resetn = ~user_boot_now;

// Reboot into the user image via the config controller. The bootloader
// bitstream (gmpack --bootaddr) stops after its final CHG_STATUS, followed
// in flash by CFGRST + JUMP to the user image. cmd.hex replays that
// CHG_STATUS with the config GPIOs handed back to the controller (see
// mkcmd.py), then RECFG makes the controller continue with the JUMP.
localparam CMD_LEN = 27;
reg [7:0] cmd_rom [0:CMD_LEN-1];
initial $readmemh("cmd.hex", cmd_rom);

localparam S_IDLE = 3'd0,
           S_EN   = 3'd1,
           S_SEND = 3'd2,
           S_NEXT = 3'd3,
           S_WAIT = 3'd4,
           S_RECFG = 3'd5;

reg [2:0] cfg_state = S_IDLE;
reg [4:0] cfg_addr = 0;
reg [3:0] cfg_wait = 0;
reg       cfg_en = 1'b0;
reg       cfg_valid = 1'b0;
reg [7:0] cfg_data = 8'h00;
reg       cfg_recfg = 1'b0;

always @(posedge clk) begin
   case (cfg_state)
      S_IDLE: if (user_boot_now && !reset_delay) begin
         cfg_addr <= 0;
         cfg_wait <= 0;
         cfg_state <= S_EN;
      end

      // EN must be high a few cycles before the first byte
      S_EN: begin
         cfg_en <= 1'b1;
         cfg_wait <= cfg_wait + 1;
         if (cfg_wait == 3) cfg_state <= S_SEND;
      end

      S_SEND: begin
         cfg_data <= cmd_rom[cfg_addr];
         cfg_valid <= 1'b1;
         cfg_state <= S_NEXT;
      end

      S_NEXT: begin
         cfg_valid <= 1'b0;
         cfg_addr <= cfg_addr + 1;
         cfg_wait <= 0;
         cfg_state <= (cfg_addr == CMD_LEN - 1) ? S_WAIT : S_SEND;
      end

      // let the controller apply CHG_STATUS before reconfiguring
      S_WAIT: begin
         cfg_en <= 1'b0;
         cfg_wait <= cfg_wait + 1;
         if (&cfg_wait) cfg_state <= S_RECFG;
      end

      S_RECFG: cfg_recfg <= 1'b1;
   endcase
end

CC_CFG_CTRL cfg_ctrl_inst (
    .CLK(clk),
    .EN(cfg_en),
    .DATA(cfg_data),
    .RECFG(cfg_recfg),
    .VALID(cfg_valid)
);

wire usb_p_tx;
wire usb_n_tx;
wire usb_p_rx;
wire usb_n_rx;
wire usb_tx_en;

// USB DFU - this instanciates the entire USB device.
usb_dfu_core dfu (
  .clk_48mhz  (clk_48mhz),
  .clk        (clk),
  .reset      (r),

  // USB signals
  .usb_p_tx( usb_p_tx ),
  .usb_n_tx( usb_n_tx ),
  .usb_p_rx( usb_p_rx ),
  .usb_n_rx( usb_n_rx ),
  .usb_tx_en( usb_tx_en ),

  // SPI
  .spi_csel( flash_csel ),
  .spi_clk( flash_sclk ),
  .spi_mosi( flash_mosi ),
  .spi_miso( flash_miso ),

  // DFU State and debug
  .dfu_detach( dfu_detach ),
  .dfu_state( dfu_state )
  //.debug( )
);

// USB Physical interface
usb_phy_gatemate phy (
  .pin_usb_p (usb_ufp_dp),
  .pin_usb_n (usb_ufp_dm),

  .usb_p_tx( usb_p_tx ),
  .usb_n_tx( usb_n_tx ),
  .usb_p_rx( usb_p_rx ),
  .usb_n_rx( usb_n_rx ),
  .usb_tx_en( usb_tx_en )
);

// USB Host Detect Pull Up
assign usb_ufp_pull = 1'b1;

endmodule
