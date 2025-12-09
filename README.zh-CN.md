# MicArray 项目概览

MicArray 是一个基于 Intel FPGA（Quartus Prime 工具链）的麦克风阵列平台，用于探索多通道音频采集、波束形成以及相关的数字信号处理，当前聚焦于 InvenSense INMP441 等数字 MEMS 麦克风前端。

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

1. **信号采集**：捕获 INMP441 数字麦克风的 I2S/PDM 数据流，在 FPGA 内部以同步时钟解串为每通道 PCM 数据。
2. **参考对齐**：选定一个麦克风通道作为参考，通过延迟线或缓冲区实现粗对齐，使所有通道共享同一帧结构。
3. **到达时间差测量**：实现交叉相关或广义交叉相关（GCC-PHAT），精确估计每个通道与参考通道之间的 TDOA。
4. **距离换算**：依据已知的声速（结合环境温湿度修正），把时间差转换为距离偏移。
5. **几何求解**：利用最小二乘或多边测量等算法，将多对距离偏移转换成麦克风相对坐标。
6. **校准闭环**：存储计算得到的位置，与预计排布比较，并输出偏差供调试和监控。

`sim/` 目录内的仿真测试将使用合成的麦克风数据验证 DSP 模块的正确性；`quartus/` 下的工程包括 HDL 模块、信号接口及约束，用于目标 Cyclone IV 器件的综合实现。

## 当前硬件进展

- 模拟 AD7606 路线已退役，系统改用 INMP441 数字 MEMS 麦克风；`doc/INMP441/INMP441.pdf` 提供新的接口要求（共享位时钟、LR 选择和单比特数据流）。
- 单麦路径已端到端打通：`RawPcmUartTop.v` 生成 BCLK/WS、采集 24 位 PCM、写入 RAM 缓冲并通过 UART 帧化发送；`scripts/test.py` 可在 PC 侧录制 5 秒 PCM 并回放/分析。

## 工具链

- **FPGA 工具**：Intel Quartus Prime（工程位于 `quartus/`）。
- **仿真**：根据个人偏好在 `sim/` 中添加支持 ModelSim、Questa 等工具的测试平台。
- **源文件组织**：HDL 源码放在 `hdl/`，约束放在 `constraints/`。

## 文档

- `doc/Log.md` 记录开发日志与工作进展。
- `doc/Style.md` 规定项目代码风格和命名。
- `doc/Timing.md` 汇总关键时序图（复位同步、I2S 时钟/采样、FIFO 握手、UART 帧化）。

## 硬件清单

- “Intel Cyclone IV EP4CE10F17C8 development board”，带板载 CH340 USB-UART。
- “InvenSense INMP441 数字 MEMS 麦克风模块”，直接向 FPGA 输出 I2S/PDM 数据流。
- “Analog Devices AD7606 8-channel simultaneous sampling ADC module”（已退役的前端）。
- “TXS0108E 8-channel bidirectional level shifter”（与 AD7606 配套的电平转换器）。