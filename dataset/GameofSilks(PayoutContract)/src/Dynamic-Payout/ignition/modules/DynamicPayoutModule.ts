import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DynamicPayoutModule", (m) => {
  const dynamicPayout = m.contract("DynamicPayout");
  return { dynamicPayout };
});
