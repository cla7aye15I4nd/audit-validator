# Tunnel

This project bridges tokens from Blockchain A to Blockchain B. The deposit logic is similar to that of an exchange but does not rely on an account system: when a supported token is deposited to a designated address on Blockchain A, the system performs a corresponding token transfer on Blockchain B to the mapped address.

In other words, when a supported token is deposited to a recognized source address on Blockchain A, the system will, after deducting bridge fees, transfer the equivalent amount of bridged tokens to the mapped destination address on Blockchain B.

To enforce access control, the system restricts access based on the IP address of the deployed machines, allowing only specified IPs.

For security and data consistency, critical information is signed and verified using AWS KMS.

System Components:
- API: The public-facing service interface. It is implemented using gRPC by default. When started with the --http parameter, the gRPC services are also exposed as HTTP APIs.
- API Manager: The user-facing backend management service, typically deployed with a dedicated IP. It works similarly to the API and also supports exposing gRPC services as HTTP via the --http parameter.
- Core: The core engine that transforms deposit transactions on Blockchain A into withdrawal tasks on Blockchain B.
- Chain API: One module per blockchain, responsible for providing deposit addresses for that chain.
- Chain Tasks: One module per blockchain, responsible for executing withdrawal tasks on that chain.
- Monitor: Deployed per blockchain, reads blocks with a delay of N blocks to detect deposits to system-controlled addresses.
- Monitor Detected: Deployed per blockchain, reads the latest blocks as quickly as possible to detect new deposits.
- Chain Manager: Deployed per blockchain, aggregates user deposits and transfers them to a designated cold wallet (not controlled by the system) or the chain's main address.

该项目用于将区块链 A 上的代币桥接至区块链 B，其充值逻辑类似于交易所，但不依赖账户系统：用户将支持的代币充值到区块链 A 上的指定地址后，系统会在区块链 B 上的对应地址发放等量的桥接代币（Bridged Token）。也就是说，任何人只要向某个受支持的区块链 A 地址充值受支持的代币，系统就会在与之映射的区块链 B 地址上，扣除系统手续费后，发放对应的桥接代币。

为实现权限控制，系统通过部署机器的 IP 地址进行限制，仅允许指定 IP 访问。

系统中的关键数据通过 AWS KMS 进行签名和验证，以确保数据的一致性与安全性。

系统模块组成：
- API：对外提供服务的公共接口，默认通过 gRPC 实现；当使用 --http 参数启动时，可将 gRPC 接口转为 HTTP 接口。
- API Manager：用户后台管理系统，通常单独部署并使用独立 IP；其接口机制与 API 相同，也支持通过 --http 参数将 gRPC 转换为 HTTP。
- Core：核心跨链逻辑，将区块链 A 的充值交易转换为区块链 B 的提现任务。
- Chain API：每条链单独部署，用于提供该链上的充值地址。
- Chain Tasks：每条链单独部署，用于执行该链的提现任务。
- Monitor：每条链单独部署，延迟读取每个新区块，用于检测是否有充值到系统地址的交易。
- Monitor Detected：每条链单独部署，尽可能快地读取新区块，用于快速检测充值。
- Chain Manager：每条链单独部署，用于归集用户充值到指定冷钱包（非系统控制）或链上主地址。


## AB Connect Testnet
- AB Connect API
  - https://api.connect.testnet.ab.org/
- AB Connect Web
  - https://app.connect.testnet.ab.org/
- AB Connect explorer
  - https://explorer.connect.testnet.ab.org/




