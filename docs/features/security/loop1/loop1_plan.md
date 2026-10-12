# Loop 1：隐私外发与请求出口

目标是处理 Android 的静默 IP 查询、Firebase Analytics、更新检查和订阅刷新请求，让用户知道外发对象、数据及网络出口，并避免代理、VPN 或核心不可用时发生未告知的直连回退和凭据泄漏。对应[审计基线](../android_security_baseline.md) A-01、A-02、A-03。

进入本 loop 时再细化产品选择、实现方案和验收。
