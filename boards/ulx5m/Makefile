##
## Make and program ULX5M
##

BASENAME = tinydfu
TARGETNAME = $(BASENAME)_ulx5m
PROJTOP = tinydfu_ulx5m

RTL_USB_DIR = ../../usb

SOURCES = \
	$(RTL_USB_DIR)/edge_detect.v \
	$(RTL_USB_DIR)/strobe.v \
	$(RTL_USB_DIR)/usb_fs_in_arb.v \
	$(RTL_USB_DIR)/usb_fs_in_pe.v \
	$(RTL_USB_DIR)/usb_fs_out_arb.v \
	$(RTL_USB_DIR)/usb_fs_out_pe.v \
	$(RTL_USB_DIR)/usb_fs_pe.v \
	$(RTL_USB_DIR)/usb_fs_rx.v \
	$(RTL_USB_DIR)/usb_fs_tx_mux.v \
	$(RTL_USB_DIR)/usb_fs_tx.v \
	$(RTL_USB_DIR)/usb_string_rom.v \
	$(RTL_USB_DIR)/usb_dfu_ctrl_ep.v \
	$(RTL_USB_DIR)/usb_spiflash_bridge.v \
	$(RTL_USB_DIR)/usb_dfu_core.v \
	$(RTL_USB_DIR)/usb_phy_gatemate.v

SRC = $(PROJTOP).v $(SOURCES)

PIN_DEF = ulx5m.ccf

# User image starts at 1MB (gmpack only accepts decimal)
BOOTADDR = 1048576

all: $(PROJTOP).bit
bootloader: $(PROJTOP).bit

synth: $(PROJTOP).json

$(PROJTOP).json: $(SRC) cmd.hex boardinfo.vh
	yosys -q -p 'synth_gatemate -top $(PROJTOP) -nomx8 -luttree -json $@' $(SRC)

$(PROJTOP).txt: $(PROJTOP).json $(PIN_DEF)
	nextpnr-himbaechel --device CCGM1A1 --json $< --vopt ccf=$(PIN_DEF) --vopt out=$@ --router router2

%.bit: %.txt cmd.hex
	gmpack --reconfig --bootaddr $(BOOTADDR) $< $@
	python3 mkcmd.py --check $@ cmd.hex

# Regenerate the CC_CFG_CTRL command stream from a bootloader build,
# then rebuild the bootloader so it contains the new cmd.hex.
cmd: $(PROJTOP).txt
	gmpack --reconfig --bootaddr $(BOOTADDR) $< cmd_tmp.bit
	python3 mkcmd.py cmd_tmp.bit cmd.hex
	rm -f cmd_tmp.bit

prog: $(PROJTOP).bit
	openFPGALoader --index-chain 0 -c gatemate_pgm $<

prog_flash: $(PROJTOP).bit
	openFPGALoader --index-chain 0 -c gatemate_pgm -f $<

# Write a user image straight to the user partition via JTAG, for testing
prog_user:
	@test -n "$(USER_BIT)" || { echo "usage: make prog_user USER_BIT=<file.bit>"; exit 1; }
	openFPGALoader --index-chain 0 -c gatemate_pgm -f -o $(BOOTADDR) $(USER_BIT)

dfu:
	dfu-util -d 16d0:116d -a0 -D test.bit

clean:
	rm -f $(PROJTOP).json $(PROJTOP).txt $(PROJTOP).bit

