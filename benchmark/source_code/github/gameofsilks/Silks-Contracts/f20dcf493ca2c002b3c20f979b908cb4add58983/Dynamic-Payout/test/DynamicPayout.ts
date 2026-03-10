import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe('DynamicPayout Contract', function () {
    async function deployDynamicPayoutFixture() {
        // Contracts are deployed using the first signer/account + 2 additional accounts
        const [addr1, addr2, addr3] = await ethers.getSigners();

        const DynamicPayout = await ethers.getContractFactory("DynamicPayout");
        const dynamicPayout = await DynamicPayout.deploy();

        return { dynamicPayout, addr1, addr2, addr3 };
    }

    interface Payment {
        payee: string;
        amount: string;
    }
    
    describe('Deployment', function () {
        it('Should assign the deployer as the initial admin and payer', async function () {
            const { dynamicPayout, addr1 } = await loadFixture(deployDynamicPayoutFixture);
            const DEFAULT_ADMIN_ROLE = await dynamicPayout.DEFAULT_ADMIN_ROLE();
            const PAYER_ROLE = await dynamicPayout.PAYER_ROLE();
            const isAdmin = await dynamicPayout.hasRole(DEFAULT_ADMIN_ROLE, addr1.address);
            const isPayer = await dynamicPayout.hasRole(PAYER_ROLE, addr1.address);

            expect(isAdmin).to.be.true;
            expect(isPayer).to.be.true;
        });
    });

    describe('Role Management', function () {
        it('Should allow admin to grant payer role to another account', async function () {
            const { dynamicPayout, addr1, addr2 } = await loadFixture(deployDynamicPayoutFixture);
            await dynamicPayout.connect(addr1).grantRole(ethers.id("PAYER_ROLE"), addr2.address);
            expect(await dynamicPayout.hasRole(ethers.id("PAYER_ROLE"), addr2.address)).to.be.true;
        });

        it('Should prevent non-admin from granting payer role', async function () {
            const { dynamicPayout, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            await expect(dynamicPayout.connect(addr2).grantRole(ethers.id("PAYER_ROLE"), addr3.address))
                .to.be.reverted;
        });

        it('Should allow admin to revoke payer role from an account', async function () {
            const { dynamicPayout, addr1, addr2 } = await loadFixture(deployDynamicPayoutFixture);
            await dynamicPayout.connect(addr1).grantRole(ethers.id("PAYER_ROLE"), addr2.address);
            await dynamicPayout.connect(addr1).revokeRole(ethers.id("PAYER_ROLE"), addr2.address);
            expect(await dynamicPayout.hasRole(ethers.id("PAYER_ROLE"), addr2.address)).to.be.false;
        });

        it('Should transfer admin role and allow new admin to manage roles', async function () {
            const { dynamicPayout, addr1, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            await dynamicPayout.connect(addr1).transferAdminRole(addr2.address);
            await dynamicPayout.connect(addr2).grantRole(ethers.id("PAYER_ROLE"), addr3.address);
            expect(await dynamicPayout.hasRole(ethers.id("PAYER_ROLE"), addr3.address)).to.be.true;
            expect(await dynamicPayout.hasRole(ethers.id("DEFAULT_ADMIN_ROLE"), addr3.address)).to.be.false;
        });
        
        it('Should prevent non-payers from calling payout', async function () {
            const { dynamicPayout, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            const payments = [
                { payee: addr2.address, amount: "1000000000000000000" }
            ];
            await expect(dynamicPayout.connect(addr3).payout(payments, { value: ethers.parseEther("1") }))
                .to.be.reverted;
        });
    });

    describe('Payout', function () {
        it('Should successfully make payments and emit events', async function () {
            const { dynamicPayout, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            const payments: Payment[] = [
                { payee: addr2.address, amount: "1000000000000000000" }, // 1 Ether in Wei
                { payee: addr3.address, amount: "2000000000000000000" }  // 2 Ether in Wei
            ];
            const totalPayout = payments.reduce((sum, payment) => {
                // Convert the string amounts to BigInt for arithmetic operations
                const sumInWei = BigInt(sum);
                const paymentInWei = BigInt(payment.amount);
        
                // Perform addition and return the sum in Wei (as string)
                return (sumInWei + paymentInWei).toString();
            }, "0"); // Initial sum as "0" Wei
            await expect(dynamicPayout.payout(payments, { value: totalPayout }))
                .to.emit(dynamicPayout, 'PaymentSent').withArgs(addr2.address, payments[0].amount)
                .to.emit(dynamicPayout, 'PaymentSent').withArgs(addr3.address, payments[1].amount)
                .to.emit(dynamicPayout, 'PayoutCompleted').withArgs(totalPayout);
        });

        it('Should fail if insufficient funds are sent for payout', async function () {
            const { dynamicPayout, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            const payments: Payment[] = [
                { payee: addr2.address, amount: "1000000000000000000" }, // 1 Ether in Wei
                { payee: addr3.address, amount: "2000000000000000000" }  // 2 Ether in Wei
            ];
            const insufficientAmount = ethers.parseEther("0.5"); // Less than required
            await expect(dynamicPayout.payout(payments, { value: insufficientAmount }))
                .to.be.revertedWith("Insufficient funds for payout");
        });

        it('Should refund excess funds to the owner', async function () {
            const { dynamicPayout, addr1, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            const payments: Payment[] = [
                { payee: addr2.address, amount: "1000000000000000000" }, // 1 Ether in Wei
                { payee: addr3.address, amount: "2000000000000000000" }  // 2 Ether in Wei
            ];
            const excessAmount = ethers.parseEther("4"); // 1 More than required
            await expect(dynamicPayout.payout(payments, { value: excessAmount }))
                .to.emit(dynamicPayout, 'RefundSent').withArgs(addr1.address, ethers.parseEther("1"));
        });

        it('Should revert if total ETH sent is less than total payout amount', async function () {
            const { dynamicPayout, addr2, addr3 } = await loadFixture(deployDynamicPayoutFixture);
            const payments: Payment[] = [
                { payee: addr2.address, amount: "1000000000000000000" }, // 1 Ether in Wei
                { payee: addr3.address, amount: "2000000000000000000" }  // 2 Ether in Wei
            ];
            const insufficientValue = ethers.parseEther("1"); 
            await expect(dynamicPayout.payout(payments, { value: insufficientValue }))
                .to.be.revertedWith("Insufficient funds for payout");
        });
    });
});
