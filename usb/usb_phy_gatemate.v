/*
  usb_phy_gatemate

  USB PHY for the GateMate Series FPGAs

  ----------------------------------------------------
  usb_phy_gatemate u_u (
    // USB pins
    .pin_usb_p( pin_usb_p ),
    .pin_usb_n( pin_usb_n ),

    // USB signals
    input  usb_p_tx,
    input  usb_n_tx,
    output usb_p_rx,
    output usb_n_rx,
    input  usb_tx_en,
  );
*/
module usb_phy_gatemate (
  // USB pins
  inout  pin_usb_p,
  inout  pin_usb_n,

  // USB signals
  input  usb_p_tx,
  input  usb_n_tx,
  output usb_p_rx,
  output usb_n_rx,
  input  usb_tx_en
);

wire usb_p_in;
wire usb_n_in;

assign usb_p_rx = usb_tx_en ? 1'b1 : usb_p_in;
assign usb_n_rx = usb_tx_en ? 1'b0 : usb_n_in;

CC_IOBUF io_p( .A( usb_p_tx ), .T( !usb_tx_en ), .Y( usb_p_in ), .IO( pin_usb_p ) );
CC_IOBUF io_n( .A( usb_n_tx ), .T( !usb_tx_en ), .Y( usb_n_in ), .IO( pin_usb_n ) );

endmodule
