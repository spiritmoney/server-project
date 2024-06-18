import { ethers } from "ethers";
import abi from "./src/abi.json"; // Converted require to import

const contractAddress = "0x6f32ae8EAcC066010F2Ffa485a099aE6b05b2a84";
const url = "https://sepolia.mode.network";

// Create a provider and contract instance
const provider = new ethers.providers.JsonRpcProvider(url);
const contract = new ethers.Contract(contractAddress, abi, provider);

// Listen for the TokenSwap event
contract.on("TokenSwap", (buyer, tokensSold, event) => {
  console.log(`TokenSwap event detected!`);
  console.log(`Buyer: ${buyer}`);
  console.log(`Tokens Sold: ${tokensSold.toString()}`);
  // Access more event properties as needed
  console.log(event); // Full event object, including transaction details
});

// Listen for the AddLiquidity event
contract.on("Add Liquidity", (provider, tokenAmounts, event) => {
  console.log(`Add Liquidity event detected!`);
  console.log(`Provider: ${provider}`);
  console.log(`Tokens Amounts: ${tokenAmounts.toString()}`);
  // Access more event properties as needed
  console.log(event); // Full event object, including transaction details
});

// Listen for the RemoveLiquidity event
contract.on(
  "Remove Liquidity",
  (provider, tokenAmounts, lpTokenSupply, event) => {
    console.log(`Remove Liquidity event detected!`);
    console.log(`Provider: ${provider}`);
    console.log(`Tokens Amounts: ${tokenAmounts.toString()}`);
    console.log(`LP Token Supply: ${lpTokenSupply.toString()}`);
    // Access more event properties as needed
    console.log(event); // Full event object, including transaction details
  }
);

async function fetchPastEvents() {
  const fromBlock = 0;
  const toBlock = "latest";

  // Fetch past TokenSwap events
  const tokenSwapEvents = await contract.queryFilter(
    contract.filters.TokenSwap(),
    fromBlock,
    toBlock
  );
  console.log(
    "Past TokenSwap Events:",
    tokenSwapEvents.map((event) => ({
      buyer: event.args?.buyer,
      tokensSold: event.args?.tokensSold.toString(),
      transactionHash: event.transactionHash,
    }))
  );

  // Fetch past AddLiquidity events
  const addLiquidityEvents = await contract.queryFilter(
    contract.filters["AddLiquidity"](),
    fromBlock,
    toBlock
  );
  console.log(
    "Past AddLiquidity Events:",
    addLiquidityEvents.map((event) => ({
      provider: event.args?.provider,
      tokenAmounts: event.args?.tokenAmounts.toString(),
      transactionHash: event.transactionHash,
    }))
  );

  // Fetch past RemoveLiquidity events
  const removeLiquidityEvents = await contract.queryFilter(
    contract.filters["RemoveLiquidity"](),
    fromBlock,
    toBlock
  );
  console.log(
    "Past RemoveLiquidity Events:",
    removeLiquidityEvents.map((event) => ({
      provider: event.args?.provider,
      tokenAmounts: event.args?.tokenAmounts.toString(),
      lpTokenSupply: event.args?.lpTokenSupply.toString(),
      transactionHash: event.transactionHash,
    }))
  );
}

fetchPastEvents().catch(console.error);
