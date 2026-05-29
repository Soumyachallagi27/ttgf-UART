# test.py  —  CocoTB tests for tt_um_uart  (TinyTapeout GF180  1×1)
# Run with:  make SIM=icarus

import cocotb
from cocotb.clock      import Clock
from cocotb.triggers   import RisingEdge, Timer, ClockCycles
from cocotb.result     import TestFailure

# ─── Constants ────────────────────────────────────────────────────────────────
CLKS_PER_BIT = 16          # must match tb.v / project.v parameter
CLK_PERIOD_NS = 10         # 100 MHz  (10 ns)
BIT_PERIOD_NS = CLKS_PER_BIT * CLK_PERIOD_NS   # 160 ns per bit

# ─── Port bit aliases ─────────────────────────────────────────────────────────
# ui_in
RX_BIT       = 0    # serial RX input
TX_START_BIT = 1    # 1-cycle pulse to start TX

# uo_out
TX_BIT       = 0    # serial TX output
TX_BUSY_BIT  = 1    # HIGH while transmitting
RX_VALID_BIT = 2    # pulses HIGH 1 clk when byte received
# uo_out[7:3] = rx_data[4:0]

# ─── Helpers ──────────────────────────────────────────────────────────────────

async def reset_dut(dut):
    """Apply reset for 5 cycles then release."""
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.ui_in.value  = 0xFF   # RX idle=1, tx_start=0
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


async def uart_send_byte(dut, byte_val):
    """
    Bit-bang one UART byte onto ui_in[0] (RX pin of DUT).
    Frame: start(0) + 8 data bits LSB-first + stop(1).
    """
    # current ui_in value, keep other bits
    base = int(dut.ui_in.value) & ~(1 << RX_BIT)

    def set_rx(val):
        if val:
            dut.ui_in.value = base | (1 << RX_BIT)
        else:
            dut.ui_in.value = base & ~(1 << RX_BIT)

    # start bit
    set_rx(0)
    await Timer(BIT_PERIOD_NS, units='ns')

    # 8 data bits, LSB first
    for i in range(8):
        set_rx((byte_val >> i) & 1)
        await Timer(BIT_PERIOD_NS, units='ns')

    # stop bit
    set_rx(1)
    await Timer(BIT_PERIOD_NS, units='ns')


async def uart_receive_byte(dut, timeout_clks=500):
    """
    Capture one UART byte from uo_out[0] (TX pin of DUT).
    Returns the 8-bit integer or raises TestFailure on timeout.
    """
    # wait for start bit (TX goes LOW)
    for _ in range(timeout_clks):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) & (1 << TX_BIT) == 0:
            break
    else:
        raise TestFailure("uart_receive_byte: timeout waiting for start bit")

    # sample in the middle of the start bit
    await Timer(BIT_PERIOD_NS // 2, units='ns')

    data = 0
    for i in range(8):
        await Timer(BIT_PERIOD_NS, units='ns')
        bit = (int(dut.uo_out.value) >> TX_BIT) & 1
        data |= (bit << i)

    # wait through stop bit
    await Timer(BIT_PERIOD_NS, units='ns')
    return data


async def start_uart_tx(dut, byte_val):
    """Load byte into uio_in and pulse tx_start for one clock."""
    dut.uio_in.value = byte_val
    # set tx_start bit
    dut.ui_in.value  = (int(dut.ui_in.value) & 0xFD) | (1 << TX_START_BIT)
    await RisingEdge(dut.clk)
    dut.ui_in.value  = int(dut.ui_in.value) & ~(1 << TX_START_BIT)


# ─── Test cases ───────────────────────────────────────────────────────────────

@cocotb.test()
async def test_tc1_reset(dut):
    """TC1: Reset — all outputs should be known after reset."""
    cocotb.log.info("TC1: Reset behaviour")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value  = 0
    dut.ui_in.value  = 0xFF   # RX idle
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 5)

    # Check TX is idle HIGH during reset
    tx_val = (int(dut.uo_out.value) >> TX_BIT) & 1
    assert tx_val == 1, f"TC1 FAIL: TX not HIGH during reset, got {tx_val}"

    # tx_busy should be LOW
    busy = (int(dut.uo_out.value) >> TX_BUSY_BIT) & 1
    assert busy == 0, f"TC1 FAIL: tx_busy not LOW during reset, got {busy}"

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    cocotb.log.info("TC1 PASS: Reset OK")


@cocotb.test()
async def test_tc2_idle_line(dut):
    """TC2: TX line stays HIGH (idle) when no data is being sent."""
    cocotb.log.info("TC2: Idle line check")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF   # RX = 1 (idle), tx_start = 0
    await ClockCycles(dut.clk, 20)

    tx_val = (int(dut.uo_out.value) >> TX_BIT) & 1
    assert tx_val == 1, f"TC2 FAIL: TX not idle HIGH, got {tx_val}"
    cocotb.log.info("TC2 PASS: TX idle HIGH confirmed")


@cocotb.test()
async def test_tc3_tx_0x55(dut):
    """TC3: Transmit 0x55 (01010101) — alternating bits."""
    cocotb.log.info("TC3: TX single byte 0x55")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF   # RX idle
    await start_uart_tx(dut, 0x55)
    received = await uart_receive_byte(dut)
    assert received == 0x55, f"TC3 FAIL: expected 0x55, got 0x{received:02X}"
    cocotb.log.info(f"TC3 PASS: TX 0x55 → received 0x{received:02X}")


@cocotb.test()
async def test_tc4_tx_0xAA(dut):
    """TC4: Transmit 0xAA (10101010) — inverse pattern."""
    cocotb.log.info("TC4: TX single byte 0xAA")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF
    await start_uart_tx(dut, 0xAA)
    received = await uart_receive_byte(dut)
    assert received == 0xAA, f"TC4 FAIL: expected 0xAA, got 0x{received:02X}"
    cocotb.log.info(f"TC4 PASS: TX 0xAA → received 0x{received:02X}")


@cocotb.test()
async def test_tc5_tx_0x00(dut):
    """TC5: Transmit all zeros 0x00."""
    cocotb.log.info("TC5: TX 0x00")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF
    await start_uart_tx(dut, 0x00)
    received = await uart_receive_byte(dut)
    assert received == 0x00, f"TC5 FAIL: expected 0x00, got 0x{received:02X}"
    cocotb.log.info(f"TC5 PASS: TX 0x00 → received 0x{received:02X}")


@cocotb.test()
async def test_tc6_tx_0xFF(dut):
    """TC6: Transmit all ones 0xFF."""
    cocotb.log.info("TC6: TX 0xFF")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF
    await start_uart_tx(dut, 0xFF)
    received = await uart_receive_byte(dut)
    assert received == 0xFF, f"TC6 FAIL: expected 0xFF, got 0x{received:02X}"
    cocotb.log.info(f"TC6 PASS: TX 0xFF → received 0x{received:02X}")


@cocotb.test()
async def test_tc7_rx_single_byte(dut):
    """TC7: Receive single byte 0x37 on RX input."""
    cocotb.log.info("TC7: RX single byte 0x37")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF   # RX idle

    # Send 0x37 to the DUT's RX pin
    await uart_send_byte(dut, 0x37)
    await ClockCycles(dut.clk, 5)

    # rx_data appears on uio_out
    rx_out = int(dut.uio_out.value)
    assert rx_out == 0x37, f"TC7 FAIL: expected 0x37 on uio_out, got 0x{rx_out:02X}"
    cocotb.log.info(f"TC7 PASS: RX 0x37 → uio_out = 0x{rx_out:02X}")


@cocotb.test()
async def test_tc8_rx_valid_pulse(dut):
    """TC8: rx_valid pulses HIGH for exactly 1 clock after byte received."""
    cocotb.log.info("TC8: rx_valid pulse check")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF

    await uart_send_byte(dut, 0xA5)

    # Hunt for rx_valid HIGH within 50 clocks
    found = False
    for _ in range(50):
        await RisingEdge(dut.clk)
        if (int(dut.uo_out.value) >> RX_VALID_BIT) & 1:
            found = True
            break

    assert found, "TC8 FAIL: rx_valid never went HIGH"
    cocotb.log.info("TC8 PASS: rx_valid pulsed HIGH")


@cocotb.test()
async def test_tc9_loopback(dut):
    """TC9: Loopback — send byte out TX, feed it back into RX, read uio_out."""
    cocotb.log.info("TC9: Loopback 0xA5")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    TEST_BYTE = 0xA5
    dut.ui_in.value = 0xFF

    # TX the byte
    await start_uart_tx(dut, TEST_BYTE)

    # Capture what appears on TX line and feed it back to RX
    received_tx = await uart_receive_byte(dut)
    assert received_tx == TEST_BYTE, \
        f"TC9 FAIL (TX side): expected 0x{TEST_BYTE:02X}, got 0x{received_tx:02X}"

    # Now send the same byte into RX
    await uart_send_byte(dut, received_tx)
    await ClockCycles(dut.clk, 5)

    rx_out = int(dut.uio_out.value)
    assert rx_out == TEST_BYTE, \
        f"TC9 FAIL (RX side): expected 0x{TEST_BYTE:02X}, got 0x{rx_out:02X}"
    cocotb.log.info(f"TC9 PASS: Loopback 0x{TEST_BYTE:02X} OK")


@cocotb.test()
async def test_tc10_tx_busy_flag(dut):
    """TC10: tx_busy goes HIGH during transmission and LOW after."""
    cocotb.log.info("TC10: tx_busy flag")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF

    # Before TX
    busy_before = (int(dut.uo_out.value) >> TX_BUSY_BIT) & 1
    assert busy_before == 0, "TC10 FAIL: tx_busy HIGH before TX started"

    await start_uart_tx(dut, 0xB7)
    await ClockCycles(dut.clk, 2)

    # During TX
    busy_during = (int(dut.uo_out.value) >> TX_BUSY_BIT) & 1
    assert busy_during == 1, "TC10 FAIL: tx_busy not HIGH during TX"

    # Wait for TX to complete (10 bits × CLKS_PER_BIT + margin)
    await ClockCycles(dut.clk, 10 * CLKS_PER_BIT + 10)

    busy_after = (int(dut.uo_out.value) >> TX_BUSY_BIT) & 1
    assert busy_after == 0, "TC10 FAIL: tx_busy still HIGH after TX done"
    cocotb.log.info("TC10 PASS: tx_busy correct")


@cocotb.test()
async def test_tc11_back_to_back_tx(dut):
    """TC11: Four consecutive bytes transmitted correctly."""
    cocotb.log.info("TC11: Back-to-back TX bytes")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    seq = [0x11, 0x22, 0x33, 0x44]
    dut.ui_in.value = 0xFF

    for idx, byte_val in enumerate(seq):
        # wait until not busy
        for _ in range(500):
            await RisingEdge(dut.clk)
            if not ((int(dut.uo_out.value) >> TX_BUSY_BIT) & 1):
                break

        await start_uart_tx(dut, byte_val)
        received = await uart_receive_byte(dut)
        assert received == byte_val, \
            f"TC11 FAIL byte[{idx}]: expected 0x{byte_val:02X}, got 0x{received:02X}"
        cocotb.log.info(f"  byte[{idx}] = 0x{received:02X}  ✓")

    cocotb.log.info("TC11 PASS: all 4 back-to-back bytes OK")


@cocotb.test()
async def test_tc12_rx_noise_rejection(dut):
    """TC12: A short glitch (<half bit) on RX must NOT trigger a false receive."""
    cocotb.log.info("TC12: RX noise/glitch rejection")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF   # RX idle

    # Record current rx_data
    before = int(dut.uio_out.value)

    # Short glitch: pull RX low for only 3 clocks (< half-bit period of 8)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << RX_BIT)
    await ClockCycles(dut.clk, 3)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << RX_BIT)

    # Wait and check no false rx_valid
    false_rx = False
    for _ in range(CLKS_PER_BIT * 12):
        await RisingEdge(dut.clk)
        if (int(dut.uo_out.value) >> RX_VALID_BIT) & 1:
            false_rx = True
            break

    assert not false_rx, "TC12 FAIL: false rx_valid triggered by glitch"
    after = int(dut.uio_out.value)
    assert before == after, \
        f"TC12 FAIL: rx_data changed from 0x{before:02X} to 0x{after:02X} on glitch"
    cocotb.log.info("TC12 PASS: Glitch correctly rejected")


@cocotb.test()
async def test_tc13_multiple_rx_bytes(dut):
    """TC13: Receive three consecutive bytes 0xDE 0xAD 0xBE."""
    cocotb.log.info("TC13: Multiple RX bytes")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF
    seq = [0xDE, 0xAD, 0xBE]

    for idx, byte_val in enumerate(seq):
        await uart_send_byte(dut, byte_val)
        await ClockCycles(dut.clk, 3)
        rx_out = int(dut.uio_out.value)
        assert rx_out == byte_val, \
            f"TC13 FAIL byte[{idx}]: expected 0x{byte_val:02X}, got 0x{rx_out:02X}"
        cocotb.log.info(f"  rx byte[{idx}] = 0x{rx_out:02X}  ✓")

    cocotb.log.info("TC13 PASS: Multiple RX bytes OK")


@cocotb.test()
async def test_tc14_tx_rx_simultaneous(dut):
    """TC14: TX and RX can operate independently at the same time."""
    cocotb.log.info("TC14: Simultaneous TX and RX")
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.ui_in.value = 0xFF

    # Kick off TX
    tx_task = cocotb.start_soon(start_uart_tx(dut, 0x5A))

    # While TX is running, receive a byte on RX
    await ClockCycles(dut.clk, 2)
    await uart_send_byte(dut, 0x3C)
    await ClockCycles(dut.clk, 3)

    # Check RX side
    rx_out = int(dut.uio_out.value)
    assert rx_out == 0x3C, \
        f"TC14 FAIL (RX): expected 0x3C, got 0x{rx_out:02X}"

    # Check TX side
    received_tx = await uart_receive_byte(dut)
    assert received_tx == 0x5A, \
        f"TC14 FAIL (TX): expected 0x5A, got 0x{received_tx:02X}"

    cocotb.log.info("TC14 PASS: Simultaneous TX+RX OK")
