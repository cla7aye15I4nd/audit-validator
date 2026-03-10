import { ethers } from "hardhat";
import { VestingTimelineHelper, VestingSchedule } from "./helper/vesting-timeline.helper";

async function main() {
    console.log("=== MWX Vesting Timeline Helper Example ===\n");

    // Example vesting schedule data
    const exampleSchedule: VestingSchedule = {
        totalVestedAmount: ethers.parseEther("1000"), // 1000 tokens for linear vesting
        releaseAmountAtCliff: ethers.parseEther("100"), // 100 tokens at cliff
        claimedAmount: ethers.parseEther("50"), // 50 tokens already claimed
        startTimestamp: BigInt(Math.floor(Date.now() / 1000)), // Start now
        cliffDuration: 30n * 24n * 3600n, // 30 days cliff
        vestingDuration: 365n * 24n * 3600n, // 1 year vesting
        releaseInterval: 28n * 24n * 3600n, // 30 days intervals
        isActive: true
    };

    const beneficiary = "0x1234567890123456789012345678901234567890";

    console.log("1. Calculating Complete Vesting Timeline");
    console.log("=".repeat(50));
    
    try {
        const timeline = VestingTimelineHelper.calculateVestingTimeline(beneficiary, exampleSchedule);
        VestingTimelineHelper.printTimeline(timeline);
    } catch (error) {
        console.error("Error calculating timeline:", error);
    }

    console.log("\n2. Current Vesting Status");
    console.log("=".repeat(50));
    
    const currentStatus = VestingTimelineHelper.getCurrentStatus(exampleSchedule);
    console.log(`Is Active: ${currentStatus.isActive}`);
    console.log(`Progress: ${currentStatus.progress.toFixed(2)}%`);
    console.log(`Currently Claimable: ${ethers.formatEther(currentStatus.currentClaimable)} tokens`);
    console.log(`Total Claimed: ${ethers.formatEther(currentStatus.totalClaimed)} tokens`);
    console.log(`Remaining Amount: ${ethers.formatEther(currentStatus.remainingAmount)} tokens`);
    
    if (currentStatus.nextClaim) {
        console.log(`Next Claim Date: ${currentStatus.nextClaim.date}`);
        console.log(`Next Claim Amount: ${ethers.formatEther(currentStatus.nextClaim.amount)} tokens`);
    } else {
        console.log("No more claims available");
    }

    console.log("\n3. Claimable Amount at Different Times");
    console.log("=".repeat(50));
    
    const now = BigInt(Math.floor(Date.now() / 1000));
    const times = [
        { name: "Now", timestamp: now },
        { name: "15 days from now", timestamp: now + (15n * 24n * 3600n) },
        { name: "30 days from now (cliff)", timestamp: now + (30n * 24n * 3600n) },
        { name: "60 days from now", timestamp: now + (60n * 24n * 3600n) },
        { name: "90 days from now", timestamp: now + (90n * 24n * 3600n) },
        { name: "1 year from now (end)", timestamp: now + (365n * 24n * 3600n) }
    ];

    times.forEach(({ name, timestamp }) => {
        const claimable = VestingTimelineHelper.calculateClaimableAmountAt(exampleSchedule, timestamp);
        const date = new Date(Number(timestamp) * 1000).toISOString();
        console.log(`${name} (${date}): ${ethers.formatEther(claimable)} tokens`);
    });

    console.log("\n4. Vesting Progress Over Time");
    console.log("=".repeat(50));
    
    const progressTimes = [
        { name: "Now", timestamp: now },
        { name: "15 days", timestamp: now + (15n * 24n * 3600n) },
        { name: "30 days (cliff)", timestamp: now + (30n * 24n * 3600n) },
        { name: "3 months", timestamp: now + (90n * 24n * 3600n) },
        { name: "6 months", timestamp: now + (180n * 24n * 3600n) },
        { name: "9 months", timestamp: now + (270n * 24n * 3600n) },
        { name: "1 year (end)", timestamp: now + (365n * 24n * 3600n) }
    ];

    progressTimes.forEach(({ name, timestamp }) => {
        const progress = VestingTimelineHelper.getVestingProgress(exampleSchedule, timestamp);
        const date = new Date(Number(timestamp) * 1000).toISOString();
        console.log(`${name} (${date}): ${progress.toFixed(2)}%`);
    });

    console.log("\n5. Next Claim Date Analysis");
    console.log("=".repeat(50));
    
    const nextClaimTimes = [
        { name: "Now", timestamp: now },
        { name: "15 days from now", timestamp: now + (15n * 24n * 3600n) },
        { name: "30 days from now (cliff)", timestamp: now + (30n * 24n * 3600n) },
        { name: "60 days from now", timestamp: now + (60n * 24n * 3600n) }
    ];

    nextClaimTimes.forEach(({ name, timestamp }) => {
        const nextClaim = VestingTimelineHelper.getNextClaimDate(exampleSchedule, timestamp);
        const date = new Date(Number(timestamp) * 1000).toISOString();
        
        if (nextClaim) {
            console.log(`${name} (${date}): Next claim at ${nextClaim.date} for ${ethers.formatEther(nextClaim.amount)} tokens`);
        } else {
            console.log(`${name} (${date}): No next claim available`);
        }
    });
}

// Example of how to use with actual contract data
async function getVestingTimelineFromContract() {
    console.log("\n=== Getting Vesting Timeline from Contract ===");
    
    try {
        // Get the vesting contract
        const vestingContract = await ethers.getContractAt("MWXVesting", "CONTRACT_ADDRESS_HERE");
        
        // Example beneficiary address (replace with actual address)
        const beneficiary = "0x1234567890123456789012345678901234567890";
        
        // Get vesting schedule from contract
        const scheduleData = await vestingContract.getVestingSchedule(beneficiary);
        
        // Convert to our interface format
        const schedule: VestingSchedule = {
            totalVestedAmount: scheduleData[0],
            releaseAmountAtCliff: scheduleData[1],
            claimedAmount: scheduleData[2],
            startTimestamp: scheduleData[3],
            cliffDuration: scheduleData[4],
            vestingDuration: scheduleData[5],
            releaseInterval: scheduleData[6],
            isActive: scheduleData[7]
        };
        
        if (schedule.isActive) {
            const timeline = VestingTimelineHelper.calculateVestingTimeline(beneficiary, schedule);
            VestingTimelineHelper.printTimeline(timeline);
            
            const status = VestingTimelineHelper.getCurrentStatus(schedule);
            console.log(`\nCurrent Status:`);
            console.log(`Progress: ${status.progress.toFixed(2)}%`);
            console.log(`Claimable: ${ethers.formatEther(status.currentClaimable)} tokens`);
        } else {
            console.log("No active vesting schedule found for this beneficiary");
        }
        
    } catch (error) {
        console.error("Error getting vesting timeline from contract:", error);
    }
}

// Run the example
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

// Uncomment to run with actual contract
// getVestingTimelineFromContract()
//     .then(() => process.exit(0))
//     .catch((error) => {
//         console.error(error);
//         process.exit(1);
//     }); 