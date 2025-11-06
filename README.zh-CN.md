# MicArray 项目概览

MicArray 是一个基于 Intel FPGA（Quartus Prime 工具链）的麦克风阵列平台，用于探索多通道音频采集、波束形成以及相关的数字信号处理。

## 项目目标

假设声源的特性已知，并布置若干麦克风；系统需要在 FPGA 上采集各个麦克风的信号，以其中一个麦克风作为参考，通过比较其余各通道与参考通道的信号到达时间差（TDOA），推算其它麦克风相对于参考点的位置，进而监控阵列几何结构的漂移。

## 仓库结构

```
MicArray/
├── build/        # Quartus 生成的比特流、时序报告及日志
├── constraints/  # 板级引脚约束与时序约束文件
├── doc/          # 项目文档与开发笔记
├── hdl/          # 可综合的 HDL 源码
├── quartus/      # Quartus 工程文件（.qpf/.qsf）和自定义 IP 的配置
├── scripts/      # 开发过程中使用的脚本
└── sim/          # 测试平台和仿真相关文件
```

Quartus 工程 (`quartus/MicArray.qpf`) 已设置输出目录为 `build/`，以避免自动生成文件污染源码目录。

## 系统工作流程

1. **信号采集**：将每个麦克风的模拟信号经 ADC 或编解码器转换为数字数据，并在 FPGA 内部以同步时钟捕获。
2. **参考对齐**：选定一个麦克风通道作为参考，通过延迟线或缓冲区实现粗对齐，使所有通道共享同一帧结构。
3. **到达时间差测量**：实现交叉相关或广义交叉相关（GCC-PHAT），精确估计每个通道与参考通道之间的 TDOA。
4. **距离换算**：依据已知的声速（结合环境温湿度修正），把时间差转换为距离偏移。
5. **几何求解**：利用最小二乘或多边测量等算法，将多对距离偏移转换成麦克风相对坐标。
6. **校准闭环**：存储计算得到的位置，与预计排布比较，并输出偏差供调试和监控。

`sim/` 目录内的仿真测试将使用合成的麦克风数据验证 DSP 模块的正确性；`quartus/` 下的工程包括 HDL 模块、信号接口及约束，用于目标 Cyclone IV 器件的综合实现。

## 当前硬件进展

- 通过 `hdl/test/ad7606_busy_loop.v` 验证了基于 BUSY 的采样闭环；示波器确认 `CONVST`、`BUSY`、`CS`、`RD` 以及 `FRSTDATA` 的时序正确。
- 使用 `TXS0108E` 电平转换器，将 AD7606 约 4 V 的数字信号转换为 Cyclone IV 所需的 3.3 V。
- UART 通道已打通：`hdl/test/uart_heartbeat.v` 和 `hdl/test/uart_sim_adc.v` 可通过板载 CH340 与电脑持续传输数据。

## 工具链

- **FPGA 工具**：Intel Quartus Prime（工程位于 `quartus/`）。
- **仿真**：根据个人偏好在 `sim/` 中添加支持 ModelSim、Questa 等工具的测试平台。
- **源文件组织**：HDL 源码放在 `hdl/`，约束放在 `constraints/`。

## 文档

- `doc/Log.md` 记录开发日志与工作进展。
- `AGENT.md` 汇总项目上下文、约定与工具链信息，供智能助手快速对齐。

## 硬件清单

- “Intel Cyclone IV EP4CE10F17C8 development board”，带板载 CH340 USB-UART。
- “Analog Devices AD7606 8-channel simultaneous sampling ADC module”。
- “TXS0108E 8-channel bidirectional level shifter”。

欢迎反馈与贡献，请遵循上述结构组织新的 HDL 模块和文档。
