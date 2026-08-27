# 预编译产物（Pre-built distribution artifacts）

无需重新编译，可直接烧录到 MemBlaze 板（xc7k325tffg900-2）使用。
构建自 commit 对应的源码；如需重建，见 `../memblaze_vio/scripts/`。

| 文件 | 用途 |
|---|---|
| `memblaze_vio_top.bit` | JTAG 在线下载。Vivado **Hardware Manager → Program Device** 选择此文件 |
| `memblaze_vio_top.ltx` | VIO 调试探针文件。Program 后关联此 `.ltx`（Hardware Manager 自动提示），打开 **hw_vio** 窗口即可看到 `vio_0` 的三个输出探针 `probe_out0/1/2`，分别对应 **LED_G(R24) / LED_Y(T20) / LED_R(T21)** |
| `memblaze_vio_top.bin` | SPIx4 配置镜像（16 MB）。板卡配置模式为 SPIx4（见 `memblaze_led.xdc`），用 Vivado **Add Configuration Memory Device** 或其它 SPI flash 烧写器写入 flash 后上电自启动 |

## 快速开始（JTAG + VIO）

```
Hardware Manager
 ├─ Open Target
 ├─ Program Device  ->  memblaze_vio_top.bit   (勾选同一目录的 .ltx)
 └─ hw_vio 窗口 vio_0
      probe_out0  <->  LED_G
      probe_out1  <->  LED_Y
      probe_out2  <->  LED_R
```

勾选 `probe_outx` 点亮对应 LED，取消则熄灭。

> 注意：`.bit` 与 `.ltx` 必须来自同一次编译，否则 Hardware Manager 会提示探针不匹配。