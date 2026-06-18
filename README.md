# 32-bit Custom MIPS Processor (3-Cycle Architecture)

A custom 32-bit MIPS processor built from scratch in Verilog, synthesized, and implemented for Xilinx 7-Series FPGA architecture. This project was built as a course project for CS220 - Computer Organization and Architecture at IIT Kanpur under the supervision of [Prof. Mainak Chaudhuri](https://www.iitk.ac.in/dr-mainak-chaudhuri).

This project demonstrates full Register Transfer Level (RTL) design, a multi-cycle finite state machine (FSM) control unit, Big-Endian sub-word memory access, and hardware-software handshaking protocols.

---

## Detailed Architecture & Execution Flow

This processor deviates from the traditional 5-stage MIPS pipeline, utilizing a highly optimized 3-Cycle Finite State Machine (FSM). This approach eliminates complex data forwarding and control hazards while maintaining distinct fetch, execute, and write-back phases to optimize the critical path.

### 1. Instruction Encoding

The control unit natively decodes standard 32-bit MIPS instruction formats, extracting the appropriate opcodes, register addresses, shift amounts, and immediate values combinationally.
* **R-Type (Register):** Used for arithmetic, shifting, and logical operations (`add`, `sub`, `and`, `sll`, `slt`).<br>`[31:26] Opcode | [25:21] rs | [20:16] rt | [15:11] rd | [10:6] shamt | [5:0] funct`
* **I-Type (Immediate):** Used for data transfer, branching, and immediate arithmetic (`lw`, `sw`, `beq`, `addi`, `lui`).<br>`[31:26] Opcode | [25:21] rs | [20:16] rt | [15:0] Immediate (Sign/Zero Extended)`
* **J-Type (Jump):** Used for unconditional control flow (`j`, `jal`).<br>`[31:26] Opcode | [25:0] Target Address`

### 2. The 3-Cycle Execution FSM

The core control logic is governed by a synchronous FSM inside `Processor.v`, managing the datapath across three primary states:

#### State 0: Fetch & Decode (`S_FETCH_READ`)
* The `ins` (instruction) wire continuously reads from the `Memory` module based on the current Program Counter (`pc`).
* The FSM combinationally decodes and latches the extracted fields into inter-stage registers (e.g., `opcode_reg`, `func_reg`, `shift_amount_reg`).
* The `RegisterFile` is accessed combinationally, latching `src1` and `src2` on the positive clock edge to ensure absolute stability for the execution phase.

#### State 1: Execute & Memory Routing (`S_EXECUTE`)
* The core `ALU` processes the registered inputs based on the opcode. It computes arithmetic results, evaluates branch conditions (`branch_taken`), or calculates effective memory addresses (Base Address + Offset).
* **Memory Routing:** If a memory read/write is required, the `data_addr_valid` flag asserts, routing the ALU's calculated byte-address to the memory controller and determining the specific access type (`READ_COMMAND`, `WRITE_COMMAND`, or `SUBWORD_WRITE_COMMAND`).
* **I/O Halts:** If a pseudo-syscall for printing or keyboard reading is detected, standard execution halts here. The FSM transitions into auxiliary wait-states to handshake with the external environment, preventing data loss.

#### State 2: Write-back & PC Update (`S_WRITEBACK`)
* The computed ALU result (`dest_data`), or the loaded memory data (`loaded_data`), is written back to the destination register. The write-enable flag (`dest_valid_reg`) is pulsed low immediately after.
* Control flow evaluates: if `branch_taken` is true, the `pc` is updated to the ALU's computed target. Otherwise, it increments linearly (`pc <= pc + 1`), and the FSM loops back to State 0.

### 3. Big-Endian Sub-Word Memory Access

A standard 32-bit memory architecture inherently loads and stores full words. To support precise byte and half-word operations, custom extraction and masking logic was engineered into the memory interface:
* **Stores (`sb`, `sh`):** The datapath fetches the *existing* 32-bit word from memory (`load_value`). Using the lowest 2 bits of the computed ALU address as a byte-offset, it dynamically masks out the targeted 8 or 16 bits, splices in the new sub-word from the source register (`src2_reg`), and issues a write-back of the newly assembled 32-bit word (`st_val`).
* **Loads (`lb`, `lbu`, `lh`, `lhu`):** The logic extracts the requested byte or half-word from the fetched 32-bit memory block. It applies either a zero-extension (for unsigned) or a sign-extension (replicating the MSB across the remaining bits) before locking it into the destination register.

---

## Key Architectural Features

* **Hardware Handshaking & Stalls:** Designed a strict synchronization protocol to bridge the megahertz-speed FPGA fabric with slower human-scale I/O. 
  * **Print Buffer:** Features a 4-slot circular array. A 5th concurrent `SYS_write` asserts `io_stall`, freezing the pipeline until the host C-program asserts `copied_io_regs`.
  * **Keyboard Interrupts:** A `SYS_read` asserts `waiting_for_input`, trapping the FSM until the user provides a keystroke and triggers `input_value_valid`.
* **Zero-Register Hardwiring:** The register file physically grounds register `$0` (`write_addr != 0` constraint), maintaining ISA compliance and preventing data cascades during branch/load zero-comparisons.
* **Integrated Performance Counters:** The `Computer.v` wrapper tracks `total_cycles` and `proc_cycles`. By pausing `proc_cycles` during I/O stalls, the architecture allows for exact, cycle-accurate measurement of CPU computation time independently of user typing speeds.

---

## File Structure

| File | Description |
| :--- | :--- |
| `Computer.v` | Top-level SoC wrapper. Multiplexes memory access between the external ARM core (for program loading) and the internal processor datapath. |
| `Processor.v` | The central brain. Houses the 3-state FSM, inter-stage registers, Big-Endian sub-word merging/extraction logic, and I/O handshaking controllers. |
| `ALU.v` | Pure combinational logic module executing arithmetic, bitwise logic, shifts, comparisons (`slt`), and memory address computation. |
| `Memory.v` | Synthesizes into Distributed RAM. Supports asynchronous reads and synchronous full-word/sub-word writes via 2-bit command flags. |
| `RegisterFile.v` | 32x32-bit storage array. Features combinational reads and negative-edge sequential writes to prevent intra-cycle read/write data corruption. |
| `defs.vh` | Header file defining all native MIPS 6-bit opcodes, ALU function codes, memory commands, and syscall identifiers. |

---
