#!/usr/bin/env python3
#
# Generate the CC_CFG_CTRL command stream that hands the configuration
# bank back to the config controller before RECFG is asserted.
#
# gmpack --bootaddr ends the bootloader bitstream with
#   CHG_STATUS(cfg, next_mode=active SPI, status bytes) ; CFGRST ; JUMP bootaddr
# and the controller stops right after CHG_STATUS. When the bitstream uses
# the config GPIOs (status byte 2, bit 0x08) the SPI pins stay in user mode,
# so the controller cannot read the JUMP. And while CFG_CPE_CFG (gmpack
# --reconfig, needed to use CC_CFG_CTRL at all) is set, RECFG does not resume
# reading from SPI. And when the bitstream uses PLL0, gmpack does not enable
# the autonomous clock (PLL_AUTN/AUTN_CT_I), so after RECFG the controller
# fails to read the flash (CFG_FAILED). We replay the final CHG_STATUS with
# both bits cleared and the autonomous clock enabled, then RECFG resumes at
# CFGRST/JUMP.
#
# usage: mkcmd.py <bootloader.bit> <cmd.hex>          write cmd.hex
#        mkcmd.py --check <bootloader.bit> <cmd.hex>  verify cmd.hex matches
import sys

CMD_FRAM = 0xd2
CMD_CFGRST = 0xc3
CMD_JUMP = 0xda
CMD_CHG_STATUS = 0xdb
CFG_CPE_CFG = 0x08
STATUS_USE_CFG_GPIOS = 0x08
CFG_PLL_AUTN = 0x04   # status byte 4 (PLL0 register A)
CFG_AUTN_CT_I = 0x01  # status byte 5 (PLL0 register B)


def crc16(data, crc=0xffff):
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc


def commands(bit):
    i = 0
    while i < len(bit):
        cmd = bit[i]
        if cmd in (0x00, 0x33):  # nop / sync
            i += 1
            continue
        hlen = 3 if cmd == CMD_FRAM else 2
        length = bit[i + 1] | (bit[i + 2] << 8 if cmd == CMD_FRAM else 0)
        data = i + hlen + 2
        yield i, cmd, bit[data:data + length]
        i = data + length + 2


def packet(cmd, data):
    hdr = bytes([cmd, len(data)])
    c = crc16(hdr)
    out = hdr + bytes([~c & 0xff, (~c >> 8) & 0xff])
    c = crc16(out + data)
    return out + data + bytes([~c & 0xff, (~c >> 8) & 0xff])


def build(bitfile):
    cmds = list(commands(open(bitfile, 'rb').read()))
    names = [c for _, c, _ in cmds[-3:]]
    if names != [CMD_CHG_STATUS, CMD_CFGRST, CMD_JUMP] or len(cmds[-3][2]) != 12:
        sys.exit(f"{bitfile}: does not end in CHG_STATUS/CFGRST/JUMP, build it with gmpack --bootaddr")
    status = bytearray(cmds[-3][2])
    status[0] &= ~CFG_CPE_CFG
    status[2] &= ~STATUS_USE_CFG_GPIOS
    status[4] |= CFG_PLL_AUTN
    status[5] |= CFG_AUTN_CT_I
    # same framing as gmpack: 4 nops, 0x33, 4 nops
    return packet(CMD_CHG_STATUS, bytes(status)) + bytes(4) + b'\x33' + bytes(4)


def main():
    args = sys.argv[1:]
    check = args[:1] == ['--check']
    if check:
        args = args[1:]
    if len(args) != 2:
        sys.exit(__doc__ or "usage: mkcmd.py [--check] <bootloader.bit> <cmd.hex>")
    bitfile, hexfile = args
    text = ''.join(f'{b:02X}\n' for b in build(bitfile))
    if check:
        if open(hexfile).read().split() != text.split():
            sys.exit(f"{hexfile} is stale for {bitfile}, run 'make cmd' and rebuild")
        return
    open(hexfile, 'w').write(text)


if __name__ == '__main__':
    main()
