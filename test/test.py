import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

CLKS_PER_BIT = 16


def get_bit(value, index):
    return (int(value) >> index) & 1


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0b00000001   # UART RX idle high
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 5)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def wait_for_status_bit(dut, bit_index, expected_value, max_cycles=500):
    for _ in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        if get_bit(dut.uio_out.value, bit_index) == expected_value:
            return

    raise AssertionError("Timeout waiting for status bit")


async def start_tx(dut, data_byte):
    dut.ui_in.value = data_byte

    # uio_in[0] = RX idle high
    # uio_in[1] = tx_start high
    dut.uio_in.value = 0b00000011
    await ClockCycles(dut.clk, 2)

    # remove tx_start, keep RX idle high
    dut.uio_in.value = 0b00000001


async def send_uart_byte_to_rx(dut, data_byte):
    # Idle line high
    dut.uio_in.value = 0b00000001
    await ClockCycles(dut.clk, 4)

    # Start bit = 0
    dut.uio_in.value = 0b00000000
    await ClockCycles(dut.clk, CLKS_PER_BIT)

    # 8 data bits, LSB first
    for i in range(8):
        rx_bit = (data_byte >> i) & 1
        dut.uio_in.value = rx_bit
        await ClockCycles(dut.clk, CLKS_PER_BIT)

    # Stop bit = 1
    dut.uio_in.value = 0b00000001

    # Wait for rx_valid pulse
    for _ in range(CLKS_PER_BIT * 3):
        await ClockCycles(dut.clk, 1)

        rx_valid = get_bit(dut.uio_out.value, 5)
        if rx_valid == 1:
            assert int(dut.uo_out.value) == data_byte
            return

    raise AssertionError("RX valid pulse not received")


@cocotb.test()
async def test_reset_outputs(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    assert int(dut.uo_out.value) == 0x00
    assert int(dut.uio_oe.value) == 0xFC

    # TX line should be idle high after reset
    assert get_bit(dut.uio_out.value, 2) == 1


@cocotb.test()
async def test_uart_tx_byte(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    data_byte = 0xA5
    await start_tx(dut, data_byte)

    # wait until TX busy is high
    await wait_for_status_bit(dut, 3, 1)

    # sample middle of start bit
    await ClockCycles(dut.clk, CLKS_PER_BIT // 2)
    assert get_bit(dut.uio_out.value, 2) == 0

    # sample data bits
    for i in range(8):
        await ClockCycles(dut.clk, CLKS_PER_BIT)
        expected_bit = (data_byte >> i) & 1
        actual_bit = get_bit(dut.uio_out.value, 2)
        assert actual_bit == expected_bit

    # sample stop bit
    await ClockCycles(dut.clk, CLKS_PER_BIT)
    assert get_bit(dut.uio_out.value, 2) == 1

    # TX done should pulse
    await wait_for_status_bit(dut, 4, 1)


@cocotb.test()
async def test_uart_rx_byte(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    await send_uart_byte_to_rx(dut, 0x3C)
    assert int(dut.uo_out.value) == 0x3C


@cocotb.test()
async def test_uart_rx_another_byte(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    await send_uart_byte_to_rx(dut, 0xA7)
    assert int(dut.uo_out.value) == 0xA7
