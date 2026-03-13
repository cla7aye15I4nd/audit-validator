import { Signer, Provider, ethers, Contract } from "ethers";
import SilksMinterFacetArtifact from "../artifacts/contracts/facets/minting/SilksMinterFacet.sol/SilksMinterFacet.json";
import { MarketplaceDiamondABI } from "../typechain-types";

export interface MintParams {
	seasonId: number;
	payoutTier: number;
	quantity: number;
	to: string;
}

// AdminOperations class defined outside of SilksMinterSDK
class AdminOperations {
	private sdk: SilksMinterSDK;

	constructor(sdk: SilksMinterSDK) {
		this.sdk = sdk;
	}

	async addContract(
		contractAddress: string,
		methodSignature: string,
		contractType: number
	): Promise<void> {
		if (!this.sdk.signer) throw new Error("Signer not set or not authorized.");
		const transaction = await this.sdk.silksMinterContract.addContract(
			contractAddress,
			methodSignature,
			contractType
		);
		await transaction.wait();
	}

	async removeContract(contractAddress: string): Promise<void> {
		if (!this.sdk.signer) throw new Error("Signer not set or not authorized.");
		const transaction = await this.sdk.silksMinterContract.removeContract(
			contractAddress
		);
		await transaction.wait();
	}

	// Other admin operations...
}

class SilksMinterSDK {
	public provider: Provider;
	public signer?: Signer;
	public admin: AdminOperations;
	public silksMinterContract: MarketplaceDiamondABI;

	private avatarContractAddress: string;
	private horseV2ContractAddress: string;

	constructor({
		providerOrSigner,
		silksMinterContractAddress,
		avatarContractAddress,
		horseV2ContractAddress,
	}: {
		providerOrSigner: Provider | Signer;
		silksMinterContractAddress: string;
		avatarContractAddress: string;
		horseV2ContractAddress: string;
	}) {
		this.avatarContractAddress = avatarContractAddress;
		this.horseV2ContractAddress = horseV2ContractAddress;

		// Adjust for Ethers v6: Check if providerOrSigner has a signMessage function to determine if it's a Signer
		if (
			"signMessage" in providerOrSigner &&
			typeof providerOrSigner.signMessage === "function"
		) {
			this.signer = providerOrSigner;
			this.provider = (providerOrSigner.provider ||
				providerOrSigner) as Provider;
			this.silksMinterContract = new ethers.Contract(
				silksMinterContractAddress,
				SilksMinterFacetArtifact.abi,
				this.signer
			) as unknown as MarketplaceDiamondABI;
		} else {
			this.provider = providerOrSigner as Provider;
			this.silksMinterContract = new ethers.Contract(
				silksMinterContractAddress,
				SilksMinterFacetArtifact.abi,
				providerOrSigner
			) as unknown as MarketplaceDiamondABI;
		}

		this.admin = new AdminOperations(this);
	}

	async mintAvatar(to: string, quantity: number): Promise<void> {
		const params: MintParams = { to, quantity, seasonId: 0, payoutTier: 0 };
		const additionalPayload = ""; // Assuming no additional payload is needed for avatars
		const avatarIds: number[] = []; // Assuming no avatar IDs needed for minting avatars
		await this.mint(
			this.avatarContractAddress,
			params,
			additionalPayload,
			avatarIds,
			ethers.parseEther("0.1")
		);
	}

	async mintHorse(
		to: string,
		seasonId: number,
		payoutTier: number,
		quantity: number,
		avatarIds: number[]
	): Promise<void> {
		const params: MintParams = { seasonId, payoutTier, quantity, to };
		const additionalPayload = ""; // Assuming specific logic is handled within the contract for horses
		await this.mint(
			this.horseV2ContractAddress,
			params,
			additionalPayload,
			avatarIds,
			ethers.parseEther("0.1")
		);
	}

	public async updateSigner(newSigner: Signer): Promise<void> {
		this.signer = newSigner;
		this.provider = newSigner.provider || this.provider;
		this.silksMinterContract = new ethers.Contract(
			await this.silksMinterContract.getAddress(),
			SilksMinterFacetArtifact.abi,
			this.signer
		) as unknown as MarketplaceDiamondABI;
	}

	private async mint(
		contractAddress: string,
		params: MintParams,
		additionalPayload: string,
		avatarIds: number[],
		value: bigint
	): Promise<void> {
		// The existing mint logic adjusted to target the correct contract
		const transaction = await this.silksMinterContract.mint(
			contractAddress,
			params,
			ethers.toUtf8Bytes(additionalPayload),
			avatarIds,
			{ value: value }
		);
		await transaction.wait();
	}
}

export default SilksMinterSDK;
