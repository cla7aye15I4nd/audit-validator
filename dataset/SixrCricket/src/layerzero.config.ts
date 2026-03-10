import { EndpointId } from '@layerzerolabs/lz-definitions'
import type { OmniPointHardhat, OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools'

const baseContract: OmniPointHardhat = {
  eid: EndpointId.BASE_V2_MAINNET,
  contractName: 'MintableOFTTestV2',
}

const bscContract: OmniPointHardhat = {
  eid: EndpointId.BSC_V2_MAINNET,
  contractName: 'MintableOFTTest',
}

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
  {
    msgType: 1,
    optionType: ExecutorOptionType.LZ_RECEIVE,
    gas: 120_000, // buffer
    value: 0,
  },
]

const pathways = [
  [
    baseContract,
    bscContract,
    [['LayerZero Labs'], []],
    [2, 2],
    [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
  ],
]

export default async function () {
  const connections = await generateConnectionsConfig(pathways)
  return {
    contracts: [{ contract: baseContract }, { contract: bscContract }],
    connections,
  }
}
