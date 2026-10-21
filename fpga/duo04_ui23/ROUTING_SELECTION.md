# UI23 构建策略

本候选沿用已验证 IO22 的路由算法 1、原器件、原时钟和管脚。IO22 的最差 setup +0.427 ns 属于基线，不能作为 UI23 的结果。本目录的 UI23 综合与布局布线需独立验收；构建期间看 `validation/build_status.json`，完成后核对 `validation/implementation_check.json` 与当前源码和位流。
