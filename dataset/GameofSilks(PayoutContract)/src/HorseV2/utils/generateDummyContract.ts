import { Contract } from "ethers";
import { EventFragment, Fragment, FunctionFragment, ParamType } from "ethers";

interface GenerateContractParams {
	diamondAddress: string;
	network: string;
	spdxIdentifier: string;
	solidityVersion: string;
	contractName: string;
}

interface GetContractStringParams extends GenerateContractParams {
	signatures: string[];
	structs: string[];
	events: string[];
}

type FacetReducerAcc<T> = T[];

export const generateDummyContract = (
	facetList: Contract[],
	{
		spdxIdentifier,
		solidityVersion,
		diamondAddress,
		network,
		contractName,
	}: GenerateContractParams
): string => {
	const structs = facetList
		.reduce<FacetReducerAcc<string>>((structsArr, contract) => {
			return [...structsArr, ...getFormattedStructs(contract)];
		}, [])
		.filter(dedoop);

	const functions = facetList
		.reduce<FacetReducerAcc<string>>((signaturesArr, contract) => {
			return [...signaturesArr, ...getFormattedFunctions(contract)];
		}, [])
		.filter(dedoop);

	const events = facetList
		.reduce<FacetReducerAcc<string>>((signaturesArr, contract) => {
			return [...signaturesArr, ...getEventSignatures(contract)];
		}, [])
		.filter(dedoop);

	const str = getContractString({
		spdxIdentifier,
		solidityVersion,
		diamondAddress,
		signatures: functions,
		structs,
		network,
		contractName,
		events,
	});

	return str;
};

/**
 * This is a generated dummy diamond implementation for compatibility with
 * etherscan. For full contract implementation, check out the diamond on louper:
 * https://louper.dev/${diamondAddress}?network=${network}
 */

const getContractString = ({
	spdxIdentifier,
	solidityVersion,
	signatures,
	structs,
	diamondAddress,
	network,
	contractName,
	events,
}: GetContractStringParams) => `
// SPDX-License-Identifier: ${spdxIdentifier}
pragma solidity ${solidityVersion};

contract ${contractName} {
${events.reduce((all, struct) => {
	return `${all}${struct}`;
}, "")}
${structs.reduce((all, struct) => {
	return `${all}${struct}`;
}, "")}
${signatures.reduce((all, sig) => {
	return `${all || "    "}${"\n"}   ${sig}`;
}, "")}
}
`;

const getEventSignatures = (facet: Contract) => {
	// const events = Object.keys(facet.interface.events);
	const events = facet.interface.fragments.filter(
		(frag) => frag.type === "event"
	) as EventFragment[];

	return events.map((event) => formatEvent(event));
};

const formatEvent = (event: EventFragment) => {
	const params: string[] = [];

	event.inputs.forEach((input) => {
		if (input.type.includes("tuple")) {
			params.push(
				`${getTupleName(input)}${input.indexed ? " indexed " : ""} ${
					input.name
				}`
			);
		} else {
			params.push(
				`${input.type}${input.indexed ? " indexed " : ""} ${input.name}`
			);
		}
	});

	const paramString = params.join(", ");
	return `    event ${event.name}(${paramString});\n`;
};

const getFormattedFunctions = (facet: Contract) => {
	const functionFragments = facet.interface.fragments.filter(
		(frag) => frag.type === "function"
	);
	return functionFragments.map((func) => formatSignature(func));
};
// const getFormattedSignatures = (facet: Contract) => {
//   const signatures = Object.keys(facet.interface.functions);

//   return signatures.map((signature) => formatSignature(facet.interface.functions[signature]));
// };

const formatSignature = (fragment: Fragment) => {
	const func = fragment as FunctionFragment; // Cast to FunctionFragment
	const paramsString = formatParams(func.inputs);

	if (!func.outputs) throw new Error("No outputs");

	const outputStr = formatParams(func.outputs);
	const stateMutability =
		func.stateMutability === "nonpayable" ? "" : ` ${func.stateMutability}`;
	const outputs = outputStr ? ` returns (${outputStr})` : "";

	return `function ${func.name}(${paramsString}) external${stateMutability}${outputs} {}`;
};
// const formatSignature = (func: FunctionFragment) => {
//   const paramsString = formatParams(func.inputs);
//   if (!func.outputs) return new Error("No outputs");
//   const outputStr = formatParams(func.outputs);

//   const stateMutability = func.stateMutability === "nonpayable" ? "" : ` ${func.stateMutability}`;
//   const outputs = outputStr ? ` returns (${outputStr})` : "";

//   return `function ${func.name}(${paramsString}) external${stateMutability}${outputs} {}`;
// };
const formatParams = (params: readonly ParamType[]): string => {
	const paramsString = params.reduce((currStr, param, i) => {
		const comma = i < params.length - 1 ? ", " : "";
		const formattedType = formatType(param);
		const name = param.name ? ` ${param.name}` : "";

		return `${currStr}${formattedType}${name}${comma}`;
	}, "");

	return paramsString;
};
// const formatParams = (params: ParamType[]): string => {
//   const paramsString = params.reduce((currStr, param, i) => {
//     const comma = i < params.length - 1 ? ", " : "";
//     const formattedType = formatType(param);
//     const name = param.name ? ` ${param.name}` : "";

//     return `${currStr}${formattedType}${name}${comma}`;
//   }, "");

//   return paramsString;
// };

const formatType = (type: ParamType, ignoreLocation = false) => {
	const storageLocation = getStorageLocationForType(type.type);
	const arrString = getArrayString(type);
	const formattedType = type.components
		? getTupleName(type) + arrString
		: type.type;

	if (ignoreLocation) return formattedType;
	return `${formattedType} ${storageLocation}`;
};
// const formatType = (type: ParamType, ignoreLocation = false) => {
//   const storageLocation = getStorageLocationForType(type.type);

//   const arrString = getArrayString(type);
//   const formattedType = type.components ? getTupleName(type) + arrString : type.type;

//   if (ignoreLocation) return formattedType;
//   return `${formattedType} ${storageLocation}`;
// };

const getArrayString = (type: ParamType): string => {
	if (!type.arrayLength) {
		return "";
	}

	if (type.arrayLength === -1) {
		return "[]";
	}

	return `[${type.arrayLength}]`;
};
// const getArrayString = (type: ParamType): string => {
//   if (!type.arrayLength) {
//     return "";
//   }

//   if (type.arrayLength === -1) {
//     return "[]";
//   }

//   return `[${type.arrayLength}]`;
// };

const getStorageLocationForType = (type: string): string => {
	// check for arrays
	if (type.indexOf("[") !== -1) {
		return "memory";
	}

	// check for tuples
	if (type.indexOf("tuple") !== -1) {
		return "memory";
	}

	switch (type) {
		case "bytes":
		case "string":
			return "memory";
		default:
			return "";
	}
};

// deterministic naming convention
const getTupleName = (param: ParamType) => {
	console.log("Tuple: ", { param });
	return `Tuple${hashCode(
		JSON.stringify(param.components || param.arrayChildren?.components)
	)}`;
};

function hashCode(str: string) {
	let hash = 0;
	for (let i = 0, len = str.length; i < len; i++) {
		const chr = str.charCodeAt(i);
		hash = (hash << 5) - hash + chr;
		hash |= 0; // Convert to 32bit integer
	}
	return hash.toString().substring(3, 10);
}

// declare structs used in function arguments
const getFormattedStructs = (facet: Contract) => {
	const fragments = [...facet.interface.fragments];

	// Functions
	const funcs = fragments.filter(
		(f): f is FunctionFragment | EventFragment =>
			f.type === "function" || f.type === "event"
	);
	const inputStructs = funcs.reduce<string[]>((inputStructsArr, func) => {
		// console.log({ func });
		const newData =
			func.name === "diamondCut"
				? getFormattedStructsFromParams(func.inputs, true)
				: getFormattedStructsFromParams(func.inputs);
		return [...inputStructsArr, ...newData];
	}, []);
	const outputStructs = funcs.reduce<string[]>((outputStructsArr, func) => {
		if (func instanceof EventFragment || !func.outputs) return [""];
		const newData =
			func.name === "diamondCut"
				? getFormattedStructsFromParams(func.outputs, true)
				: getFormattedStructsFromParams(func.outputs);
		return [...outputStructsArr, ...newData];
	}, []);

	return [...inputStructs, ...outputStructs];
};

const getFormattedStructsFromParams = (
	params: readonly ParamType[],
	debug = false
): string[] => {
	const returnData = params
		.map(recursiveFormatStructs)
		.flat()
		.filter((str) => {
			if (debug) {
				console.log({ str });
			}
			return str.indexOf(" struct ") !== -1;
		});
	if (debug) {
		console.log({ params, returnData });
	}
	return returnData;
};

const recursiveFormatStructs = (param: ParamType): string[] => {
	// base case
	let components: readonly ParamType[] | undefined | null = [];
	if (!param.components && !param.arrayChildren?.components) {
		return [""];
	} else {
		components = param.components || param.arrayChildren?.components;
	}

	const otherStructs = components
		?.map(recursiveFormatStructs)
		.flat()
		.filter((str) => str.indexOf(" struct ") !== -1);

	const structMembers = components?.map(formatStructMember);
	const struct = `    struct ${getTupleName(param)} {${structMembers?.reduce(
		(allMembers, member) => `${allMembers}${member}`,
		""
	)}\n    }`;

	if (!otherStructs) return [struct];
	return [struct, ...otherStructs];
};

const formatStructMember = (param: ParamType) => {
	const arrString = getArrayString(param);
	return `\n        ${
		param.components ? getTupleName(param) + arrString : param.type
	} ${param.name};`;
};

const dedoop = (str: string, index: number, allmembers: string[]) => {
	for (let i = 0; i < index; i++) {
		if (allmembers[i] === str) {
			return false;
		}
	}

	return true;
};
